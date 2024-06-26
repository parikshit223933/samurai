require "samurai/version"
require 'thor'
require 'octokit'
require 'json'
require 'fileutils'
require 'highline'
require 'slack-notifier'
require 'time'
require 'rest-client'

module Samurai
  class CLI < Thor
    VERSION = "0.1.0"
    CONFIG_FILE = File.join(Dir.home, '.samurai.config')

    desc "config", "Interactive configuration for the samurai"

    # CONFIG OPTIONS
    attr_accessor :source_branch_name,
                  :token,
                  :target_branch_name,
                  :inform_on_slack,
                  :slack_channel_name,
                  :slack_user_name,
                  :slack_webhook_url,
                  :slack_icon_emoji

    def config
      hl = HighLine.new
      config = load_config

      repo = hl.ask("Enter the GitHub repository local setup location: ") do |q|
        q.default = Dir.pwd # Set default to the directory name
      end

      default_token = config.dig(Dir.pwd, 'token')
      num_chars_to_show = 5
      if default_token
        displayed_chars = [default_token.length, num_chars_to_show].min
        masked_token = "#{default_token[0, displayed_chars]}#{'*' * (default_token.length - displayed_chars)}"
      else
        masked_token = ''
      end
      token = hl.ask("Enter your GitHub token: #{masked_token}") do |q|
        q.echo = '*'
      end
      token = token != '' ? token : default_token

      default_source_branch = config.dig(Dir.pwd, 'source_branch_name') || 'staging'
      source_branch_name = hl.ask("What is your source branch?") do |q|
        q.default = default_source_branch
      end

      default_target_branch = config.dig(Dir.pwd, 'target_branch_name') || 'master'
      target_branch_name = hl.ask("What is your target branch?") do |q|
        q.default = default_target_branch
      end

      default_value_for_inform_on_slack = config.dig(Dir.pwd, 'inform_on_slack') || 'yes'
      inform_on_slack = hl.ask("Inform about releases on slack?") do |q|
        q.default = default_value_for_inform_on_slack
      end

      slack_channel_name = nil
      slack_user_name = nil
      slack_webhook_url = nil
      slack_icon_emoji = nil
      if inform_on_slack.downcase == 'yes'
        default_slack_channel_name = config.dig(Dir.pwd, 'slack_channel_name') || 'releases'
        slack_channel_name = hl.ask("Enter the slack channel name") do |q|
          q.default = default_slack_channel_name
        end
        default_slack_user_name = config.dig(Dir.pwd, 'slack_user_name') || 'Bot'
        slack_user_name = hl.ask("Enter the slack user name") do |q|
          q.default = default_slack_user_name
        end
        default_slack_webhook_url = config.dig(Dir.pwd, 'slack_webhook_url')
        slack_webhook_url = hl.ask("Enter the slack webhook url") do |q|
          q.default = default_slack_webhook_url
        end
        default_slack_icon_emoji = config.dig(Dir.pwd, 'slack_icon_emoji')
        slack_icon_emoji = hl.ask("What slack icon emoji do you want to use?") do |q|
          q.default = default_slack_icon_emoji
        end
      end

      config[repo] = { token: token,
                       source_branch_name: source_branch_name,
                       target_branch_name: target_branch_name,
                       inform_on_slack: inform_on_slack,
                       slack_channel_name: slack_channel_name,
                       slack_user_name: slack_user_name,
                       slack_webhook_url: slack_webhook_url,
                       slack_icon_emoji: slack_icon_emoji }
      save_config(config)
      puts "Configuration saved for #{repo}"
    end

    desc "execute", "Prepare for deployment"

    def execute
      @current_directory = Dir.pwd
      config = load_config
      current_config = config.dig(@current_directory)
      if current_config.nil?
        puts 'This directory is not configured to use samurai. Please use "samurai config" to setup'
        exit(1)
      end

      @source_branch_name = current_config.dig('source_branch_name')
      @target_branch_name = current_config.dig('target_branch_name')
      @token = current_config.dig('token')
      @inform_on_slack = current_config.dig('inform_on_slack').downcase == 'yes'
      @slack_channel_name = current_config.dig('slack_channel_name')
      @slack_user_name = current_config.dig('slack_user_name')
      @slack_webhook_url = current_config.dig('slack_webhook_url')
      @slack_icon_emoji = current_config.dig('slack_icon_emoji')

      puts 'Make sure your paths are clean and there is nothing to commit'

      puts 'Stashing existing changes (if any)'
      `git add . && git stash`
      puts 'Resetting original repository state'
      `git reset`
      puts "Pulling #{@target_branch_name}"
      `git checkout #{@target_branch_name} && git pull`
      puts "Pulling #{@source_branch_name}"
      `git checkout #{@source_branch_name} && git pull`

      current_date = DateTime.now.strftime('%d.%m.%y_%H_%M')
      release_branch_name = "release-#{current_date}"
      `git checkout -b #{release_branch_name}`
      puts "Created a release branch #{release_branch_name}"
      `git push -u origin #{release_branch_name} --no-verify`
      puts "Pushed release branch #{release_branch_name}"

      json_response = create_release_pr(fetch_repo_name, release_branch_name)
      release_pr_url = json_response['html_url']
      puts "Created Release PR #{release_pr_url}"
      system('open', release_pr_url) # macos only

      hl = HighLine.new
      _res = hl.ask("Please approve the PR, Merge it and press enter to proceed")
      puts 'Fetching release PR details...'
      if @inform_on_slack
        release_pr_id = json_response['number']
        repo = fetch_repo_name
        release_pr_details = fetch_release_pr_details(repo, release_pr_id)
        send_slack_message(repo, release_pr_details, release_pr_url)
      end

      `git checkout #{@target_branch_name} && git pull origin #{@target_branch_name}`
      `git tag #{current_date} -m "#{release_branch_name}"`
      `git push origin #{@target_branch_name} --no-verify --follow-tags`
      puts "PUSHED #{@target_branch_name} AND TAG #{current_date}"
    end

    private

    def send_slack_message(repo, release_pr_details, release_pr_url)
      notifier = Slack::Notifier.new @slack_webhook_url
      message = build_slack_message(repo, release_pr_details, release_pr_url)

      notifier.ping message,
                    channel: "##{@slack_channel_name}",
                    username: @slack_user_name,
                    icon_emoji: ":#{@slack_icon_emoji}:"
    end

    def build_slack_message(repo, release_pr_details, release_pr_url)
      message = ":newspaper: Hey everyone, details for today's deployment:\n"
      message += "Apps Deployed: #{repo}\n"
      message += "Release details:\n"
      message += "<#{release_pr_url}|Release PR> :motorway:\n"

      release_pr_details.each do |pr_number, details|
        merged_at_ist = convert_to_ist(details[:pr_merged_at])
        created_at_ist = convert_to_ist(details[:pr_created_at])
        pr_url = "https://github.com/#{repo}/pull/#{pr_number}"

        message += "\n*<#{pr_url}|PR ##{pr_number}>:* *`#{details[:pr_title]}`* (#{details[:pr_creator]})\n"
        message += ":clock1: *Created at:* #{created_at_ist}\n"
        message += ":clock2: *Merged at:* #{merged_at_ist} by #{details[:merger]}\n"
        message += ":eyes: *Reviewed by:* #{details[:reviewer]}\n"
        message += ":star: *Major Contributors:* #{details[:major_contributors].join(', ')}\n"

        unless details[:minor_contributors].empty?
          message += ":small_blue_diamond: *Minor Contributors:* #{details[:minor_contributors].join(', ')}\n"
        end

        unless details[:contributors_with_only_merge_commit_with_base_branch].empty?
          message += ":twisted_rightwards_arrows: *Merge commits performed by:* #{details[:contributors_with_only_merge_commit_with_base_branch].join(', ')}\n"
        end
      end

      message
    end

    def convert_to_ist(utc_time)
      Time.parse(utc_time.to_s).getlocal('+05:30').strftime('%d %B %Y, %I:%M%p')
    end

    def fetch_release_pr_details(repo, pr_number)
      client = client_for(@current_directory)
      pr_number = pr_number.to_i

      release_pr_commits = fetch_all_commits(client, repo, pr_number)
      commit_messages = release_pr_commits.map { |commit| commit.commit.message }
      pr_numbers = extract_pr_numbers(commit_messages)

      contributors_hash = {}

      pr_numbers.each do |sub_pr_number|
        pr = client.pull_request(repo, sub_pr_number)
        pr_commits = client.pull_request_commits(repo, sub_pr_number)
        pr_reviews = client.pull_request_reviews(repo, sub_pr_number)

        contributors = Hash.new(0)
        merge_commit_contributors = []

        pr_commits.each do |commit|
          author = commit.author&.login
          if author
            if merge_commit?(commit)
              merge_commit_contributors << author
            else
              contributors[author] += 1
            end
          end
        end

        max_commits = contributors.values.max
        major_contributors = contributors.select { |_, count| count == max_commits }.keys
        minor_contributors = contributors.select { |_, count| count != max_commits }.keys
        merge_commit_only_contributors = merge_commit_contributors.uniq - contributors.keys

        merger = pr.merged_by&.login
        reviewer = pr_reviews.map { |review| review.user.login }.uniq.first

        contributors_hash[sub_pr_number] = {
          major_contributors: major_contributors,
          minor_contributors: minor_contributors,
          reviewer: reviewer,
          merger: merger,
          contributors_with_only_merge_commit_with_base_branch: merge_commit_only_contributors,
          pr_creator: pr.user.login,
          pr_title: pr.title,
          pr_created_at: pr.created_at,
          pr_merged_at: pr.merged_at
        }
      end

      contributors_hash
    end

    def fetch_all_commits(client, repo, pr_number)
      commits = []
      page = 1

      loop do
        response = client.pull_request_commits(repo, pr_number, per_page: 100, page: page)
        break if response.empty?
        commits.concat(response)
        page += 1
      end

      commits
    end

    def fetch_repo_name
      remote_url = `git config --get remote.origin.url`.strip
      if remote_url.empty?
        raise 'Remote origin URL not found. Make sure you are in a Git repository with a remote origin.'
      end

      # Handle different URL formats
      if remote_url =~ /github.com[:\/](.+\/.+)\.git/
        repo_name = $1
      else
        raise 'Unsupported remote URL format. Expected GitHub repository URL.'
      end

      repo_name
    end

    def load_config
      if File.exist?(CONFIG_FILE)
        JSON.parse(File.read(CONFIG_FILE))
      else
        {}
      end
    end

    def save_config(config)
      File.write(CONFIG_FILE, JSON.pretty_generate(config))
    end

    def client_for(directory)
      config = load_config
      token = config.dig(directory, 'token')
      unless token
        puts "Repository not configured. Run 'samurai config'"
        exit(1)
      end
      Octokit::Client.new(access_token: token)
    end

    def extract_pr_numbers(commit_messages)
      pr_numbers = []
      commit_messages.each do |message|
        matches = message.scan(/#(\d+)/)
        pr_numbers.concat(matches.flatten)
      end
      pr_numbers.uniq
    end

    def merge_commit?(commit)
      commit.parents.size > 1
    end

    def create_release_pr(repo, release_branch_name)
      headers = { 'Authorization': "token #{@token}", 'accept': 'application/vnd.github.v3+json' }
      mr_title = release_branch_name.split('-').join(' ').capitalize
      body = {
        head: release_branch_name,
        base: @target_branch_name,
        title: mr_title
      }
      url = "https://api.github.com/repos/#{repo}/pulls"
      begin
        res = RestClient.post(url, body.to_json, headers)
        JSON.parse(res.body)
      rescue StandardError => e
        pp JSON.parse(@e.response.body)['errors']
        exit(1)
      end
    end
  end
end


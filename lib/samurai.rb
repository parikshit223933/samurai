require "samurai/version"
require 'thor'
require 'octokit'
require 'json'
require 'fileutils'
require 'highline'

module Samurai
  class CLI < Thor
    VERSION = "0.1.0"
    CONFIG_FILE = File.join(Dir.home, '.samurai.config')

    desc "config", "Interactive configuration for the samurai"
    def config
      hl = HighLine.new
      config = load_config

      repo = hl.ask("Enter the GitHub repository (e.g., 'owner/repo'): ")
      token = hl.ask("Enter your GitHub token: ") { |q| q.echo = '*' }

      config[repo] = { token: token }
      save_config(config)
      puts "Configuration saved for #{repo}"
    end

    desc "deploy REPO PR_NUMBER", "Prepare deployment details for the given release PR"
    def deploy(repo, pr_number)
      client = client_for(repo)
      pr_number = pr_number.to_i

      release_pr_commits = client.pull_request_commits(repo, pr_number)
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
          contributors_with_only_merge_commit_with_base_branch: merge_commit_only_contributors
        }
      end

      puts JSON.pretty_generate(contributors_hash)

      File.open('contributors.json', 'w') do |file|
        file.write(JSON.pretty_generate(contributors_hash))
      end
    end

    private

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

    def client_for(repo)
      config = load_config
      token = config.dig(repo, 'token')
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
  end
end


# Samurai

Samurai is a command line tool to simplify and automate deployment initiation process for your projects hosted on github.
This tool integrates with GitHub, Slack, and utilizes several Ruby gems to streamline the creation of release branches, pull requests, and notifications.

## Installation

### Building from source
To install this gem
1. Clone the Repo
2. cd into the repo location on your local system
3. Run: `gem build samurai.gemspec && gem install samurai-0.1.0.gem`
4. Run `echo 'export PATH="$HOME/.gem/bin:$PATH"' >> ~/.zshrc`

### Using prebuilt gem from releases
1. Go to releases and download the latest release
2. Run: `gem install samurai-0.1.0.gem`

> On rubygems.org, there is another gem with the same name, thats why this specific gem cannot be installed with `gem install samurai
`

## Configuration
Before using Samurai, you need to configure it for your repository. This configuration includes setting up your GitHub token, source and target branches, and Slack notifications if needed.
Run the following command at the location of your github repo setup on your local system to start the interactive configuration process
```sh
samurai config
```

This command will prompt you to enter the necessary configuration details, including:

- GitHub repository location
- GitHub token
- Source branch name (default: staging)
- Target branch name (default: master)
- Slack notification preferences

If you choose to inform about releases on Slack, you will also be prompted to enter
- Slack channel name
- Slack user name
- Slack webhook URL
- Slack icon emoji

The configuration is saved in `~/.samurai.config`.

## Usage
Once configured, you can use Samurai to prepare for deployment by executing the following command:
```shell
samurai execute
```

This command will:

- Stash any existing changes.
- Reset the repository to its original state.
- Pull the latest changes from the target branch.
- Pull the latest changes from the source branch.
- Create a new release branch.
- Push the release branch to the remote repository.
- Create a pull request for the release branch.
- Notify the configured Slack channel about the release (if enabled).

## Example
```shell
$ samurai config
Enter the GitHub repository local setup location: /path/to/repo
Enter your GitHub token: **********
What is your source branch? (staging)
What is your target branch? (master)
Inform about releases on slack? (yes)
Enter the slack channel name (releases)
Enter the slack user name (Bot)
Enter the slack webhook url: https://hooks.slack.com/services/your/webhook/url
What slack icon emoji do you want to use? (:rocket:)

Configuration saved for /path/to/repo
```

```shell
$ samurai execute
Make sure your paths are clean and there is nothing to commit
Stashing existing changes (if any)
Resetting original repository state
Pulling master
Pulling staging
Created a release branch release-14.06.24_12_30
Pushed release branch release-14.06.24_12_30
Created Release PR https://github.com/your/repo/pull/123
Fetching release PR details...
PUSHED master AND TAG 14.06.24_12_30
```

## Development
To contribute to Samurai, follow these steps:

- Fork the repository.
- Create a feature branch (git checkout -b feature-branch).
- Commit your changes (git commit -am 'Add new feature').
- Push to the branch (git push origin feature-branch).
- Create a new Pull Request.

> Tip You can use a single comand to test your changes: `rm -rf
samurai-0.1.0.gem && gem uninstall samurai && gem build samurai.gemspec && gem install samurai-0.1.0.gem
`

## License
Samurai is available under the MIT License.

## Acknowledgements
Samurai uses the following Ruby gems:

- Thor for command-line interface
- Octokit for GitHub API integration
- HighLine for interactive command-line input
- Slack Notifier for Slack notifications
- RestClient for making HTTP requests


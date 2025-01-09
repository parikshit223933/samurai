require_relative 'lib/samurai/version'

Gem::Specification.new do |spec|
  spec.name          = "samurai"
  spec.version       = Samurai::VERSION
  spec.authors       = ["Parikshit Singh"]
  spec.email         = ["pk223933@gmail.com"]

  spec.summary       = %q{A tool for preparing deployment details from GitHub release pull requests}
  spec.description   = %q{Samurai is a command-line tool to automate the preparation of deployment details from GitHub release pull requests.}
  spec.homepage      = "https://github.com/parikshit223933/samurai"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/parikshit223933/samurai"
  spec.metadata["changelog_uri"] = "https://github.com/parikshit223933/samurai/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3.1"
  spec.add_dependency "octokit", "~> 8.1.0"
  spec.add_dependency "highline", "~> 2.1.0"
  # spec.add_dependency "faraday-retry", "~> 2.2.1"
  spec.add_dependency "rest-client", "~> 2.1.0"
  spec.add_dependency "slack-notifier", "~> 2.4.0"
  spec.add_dependency "mail", "~> 2.7.1"

  spec.add_development_dependency "bundler", "~> 2.1.4"
  spec.add_development_dependency "rake", "~> 13.0.6"
end

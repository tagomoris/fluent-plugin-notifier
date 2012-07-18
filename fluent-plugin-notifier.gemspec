# -*- encoding: utf-8 -*-
Gem::Specification.new do |gem|
  gem.name          = "fluent-plugin-notifier"
  gem.version       = "0.0.2"
  gem.authors       = ["TAGOMORI Satoshi"]
  gem.email         = ["tagomoris@gmail.com"]
  gem.summary       = %q{check matched messages and emit alert message}
  gem.description   = %q{check matched messages and emit alert message with throttling by conditions...}
  gem.homepage      = "https://github.com/tagomoris/fluent-plugin-notifier"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_development_dependency "fluentd"
  gem.add_runtime_dependency "fluentd"
end

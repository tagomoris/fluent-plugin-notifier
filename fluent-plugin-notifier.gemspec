# -*- encoding: utf-8 -*-
Gem::Specification.new do |gem|
  gem.name          = "fluent-plugin-notifier"
  gem.version       = "0.2.4"
  gem.authors       = ["TAGOMORI Satoshi"]
  gem.email         = ["tagomoris@gmail.com"]
  gem.summary       = %q{check matched messages and emit alert message}
  gem.description   = %q{check matched messages and emit alert message with throttling by conditions...}
  gem.homepage      = "https://github.com/tagomoris/fluent-plugin-notifier"
  gem.license       = "Apache-2.0"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_development_dependency "appraisal"
  gem.add_development_dependency "test-unit"
  gem.add_development_dependency "rake"
  gem.add_runtime_dependency "fluentd", [">= 0.10.0", "< 2.0"]
end

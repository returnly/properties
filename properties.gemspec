$:.push File.expand_path("../lib", __FILE__)

require "properties/version"

Gem::Specification.new do |s|
  s.name        = "properties"
  s.version     = Properties::VERSION
  s.authors     = ["Marcos Sainz"]
  s.email       = ["marcos@returnly.com"]
  s.homepage    = "https://bitbucket.org/returnly/returnly-gems/properties"
  s.summary     = "Summary of Properties"
  s.description = "Description of Properties"
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["spec/**/*"]

  s.add_dependency "rails", "> 4.2.5", "< 6.0"
  s.add_dependency "composite_primary_keys"
  s.add_dependency "upsert", "~> 2.1.2"
  s.add_dependency "mysql2", ">= 0.3.13", "< 0.5"

  # s.add_development_dependency "sqlite3"
  s.add_development_dependency "rspec-rails"
  s.add_development_dependency "factory_girl_rails"
  s.add_development_dependency "faker"
  s.add_development_dependency "database_cleaner"
end

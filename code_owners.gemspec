$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
name = "code_owners"
require "#{name}/version"

Gem::Specification.new name, CodeOwners::VERSION do |s|
  s.date          = "2018-03-29"
  s.summary       = ".github/CODEOWNERS introspection utility gem"
  s.description   = "utility gem for .github/CODEOWNERS introspection"
  s.authors       = "Jonathan Cheatham"
  s.email         = "coaxis@gmail.com"
  s.homepage      = "https://github.com/jcheatham/#{s.name}"
  s.licenses      = "MIT"

  s.files         = `git ls-files`.split("\n")
  s.bindir        = 'bin'
  s.test_files    = `git ls-files -- test/*`.split("\n")
  s.require_paths = ["lib"]
  s.executables   = ["code_owners"]

  s.add_development_dependency "rspec"
  s.add_runtime_dependency "rake"
end

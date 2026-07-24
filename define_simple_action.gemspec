# frozen_string_literal: true

require_relative 'lib/define_simple_action/version'

Gem::Specification.new do |spec|
  spec.name = 'define_simple_action'
  spec.version = DefineSimpleAction::VERSION
  spec.authors = ['Stanislav Vorobyev']
  spec.email = ['vs@megaperfume.ru']

  spec.summary = 'Rails controller concern that generates simple CRUD actions by naming convention'
  spec.description = 'Dynamically defines index/show/create/update/destroy (and custom) controller actions ' \
                      'that resolve service, contract and params by convention. Serialization, caching and ' \
                      'authorization are left to the host app via overridable hooks.'
  spec.homepage = 'https://github.com/Randewoo-Tech/define_simple_action'
  spec.required_ruby_version = '>= 3.2.0'
  spec.license = 'MIT'

  spec.metadata['homepage_uri'] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Используем camelize/constantize/deep_symbolize_keys/exclude? — конвенции резолвинга
  # завязаны на них. В хост-приложении (Rails) ActiveSupport и так есть, но объявляем
  # зависимость явно, а не полагаемся на порядок загрузки.
  spec.add_dependency 'activesupport', '>= 6.1', '< 9'

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end

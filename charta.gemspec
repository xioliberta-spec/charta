require_relative 'lib/charta/version'

Gem::Specification.new do |spec|
  spec.name = 'charta'
  spec.version = Charta::VERSION
  spec.authors = ['Ekylibre developers']
  spec.email = ['dev@ekylibre.com']

  spec.summary = 'Simple tool over geos and co'
  spec.required_ruby_version = '>= 2.6.0'
  spec.homepage = 'https://gitlab.com/ekylibre'
  spec.license = 'AGPL-3.0-only'

  spec.files = Dir.glob(%w[lib/**/*.rb *.gemspec])

  spec.require_paths = ['lib']

  spec.add_dependency 'activesupport', '>= 5.0', '< 7.2'
  spec.add_dependency 'json', '>= 1.8.0'
  spec.add_dependency 'nokogiri', '>= 1.7.0'
  spec.add_dependency 'rgeo', '~> 2.0'
  spec.add_dependency 'rgeo-geojson', '~> 2.0'
  # Palier 5: 2.0.1 needs the legacy proj_api.h header, which PROJ dropped
  # entirely (deprecated since PROJ 5, gone by PROJ 7/8) -- its native ext
  # silently fails to build against modern libproj-dev, and Proj4.supported?
  # returns false. 3.1.x uses the modern proj.h API while staying on
  # rgeo ~> 2.0 (4.0+ requires rgeo ~> 3.0, a bigger, separate jump).
  spec.add_dependency 'rgeo-proj4', '~> 3.1'
  spec.add_dependency 'victor', '~> 0.3.3'
  spec.add_dependency 'zeitwerk', '>= 2.4.0'

  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'rake', '~> 12.0'
  spec.add_development_dependency 'rubocop', '1.3.1'
end

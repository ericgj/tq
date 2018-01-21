require_relative 'lib/version'

Deps = ->{
  File.readlines('./.gems').map { |line|
    line.chomp.split(/\s+/).select {|it| it != '-v' }
  }
}

Gem::Specification.new do |s|
  s.name = 'tq'
  s.version = TQ::VERSION
  s.summary = 'Ruby client for Google Cloud Tasks (REST API v2beta2)'
  s.description = 'A simple framework for writing task worker processes'
  s.licenses = ['MIT']
  s.authors = ['Eric Gjertsen']
  s.email = 'ericgj72@gmail.com'
  s.files = ['.gems'] +
            Dir['lib/*.rb'] + 
            Dir['lib/tq/*.rb'] + 
            Dir['test/*.rb']
  s.homepage = 'https://github.com/ericgj/tq'

  Deps[].each do |(gem, vers)|
    if gem == 'minitest'
      s.add_development_dependency gem, '= ' + vers
    else
      s.add_runtime_dependency gem, '= ' + vers
    end
  end

end


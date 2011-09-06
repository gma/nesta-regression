#!/usr/bin/env ruby

require 'net/http'

class Theme < Struct.new(:name)
  def self.all
    dir = File.join(File.expand_path('..', File.dirname($0)), 'themes')
    names = Dir.glob("#{dir}/*").map { |path| File.basename(path) }
    names.unshift('default').map { |name| new(name) }
  end

  def enable
    if name == 'default'
      lines = File.readlines('config/config.yml').select do |line|
        line !~ /theme/
      end
      File.open('config/config.yml', 'w') { |f| f.write(lines.join('')) }
    else
      system("bundle exec nesta theme:enable #{name}")
    end
  end
end

class Tester < Struct.new(:release_path, :theme)
  LOCAL_URL = 'http://localhost:9393'

  def initialize
    @failures = {}
    @failure_count = 0
    super
  end

  def update_dependencies
    puts "Running bundle in #{Dir.pwd}"
    system('bundle update')
  end

  def start_server
    puts "Starting Nesta in #{Dir.pwd}"
    @server = IO.popen(['shotgun', 'config.ru'])
    attempts = 0
    while attempts < 10
      begin
        Net::HTTP.get_response(URI.parse(LOCAL_URL))
      rescue Errno::ECONNREFUSED
        sleep 0.5
        attempts += 1
      else
        break
      end
    end
  end

  def stop_server
    puts "Stopping Nesta in #{Dir.pwd}"
    Process.kill('TERM', @server.pid)
  end

  def get(url)
    response = Net::HTTP.get_response(URI.parse(url))
    yield(response)
  end

  def assert(predicate, message = nil)
    if ! predicate
      @failure_count += 1
      @failures[release_path] ||= []
      @failures[release_path] << "#{message} [#{theme} theme]"
    end
  end

  def check_pages
    puts "Checking pages"
    get(LOCAL_URL) do |response|
      assert(response.code == '200', "Expected 200 for #{LOCAL_URL}")
    end
  end

  def check_stylesheets
    puts "Checking stylesheets"
  end

  def releases_dir
    File.join(File.expand_path('..', File.dirname($0)), 'releases')
  end

  def main
    Dir.glob("#{releases_dir}/*").each do |path|
      Dir.chdir(path)
      self.release_path = path
      update_dependencies
      start_server
      Theme.all.each do |theme|
        puts "Switching theme to #{theme.name}"
        theme.enable
        self.theme = theme.name
        check_pages
        check_stylesheets
      end
      stop_server
    end

    report_on_failures
  end

  def report_on_failures
    @failures.keys.each do |path|
      $stderr.puts "Errors in #{path}:"
      @failures[path].each do |message|
        $stderr.puts message
      end
    end

    $stderr.puts
    $stderr.puts "Failures: #{@failure_count}"
  end
end

Tester.new.main

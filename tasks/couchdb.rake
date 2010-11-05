# Building CouchDB

require 'uri'
require 'tmpdir'

namespace :couchdb do

  couchdb_build_deps = ['erlang:build', 'build:os_dependencies', 'tracemonkey:build', 'icu:build', :known_distro, 'environment:path']

  desc 'Build the requirements for CouchDB'
  task :deps => couchdb_build_deps
  task :dependencies => :deps

  desc 'Build CouchDB'
  task :build => couchdb_build_deps + [:plugins, COUCH_BIN]

  desc 'Build CouchDB and then clean out unnecessary things like autotools'
  task :clean_install => :build do
    %w[ erlang toolchain ].each do |section|
      run_task "#{section}:clean"
    end

    %w[ include ].each do |dir|
      FileUtils.rm_rf "#{BUILD}/#{dir}"
    end
  end

  file COUCH_SOURCE => :known_distro do
    git_checkout(ENV['git']) if ENV['git']
  end

  task :plugins => COUCH_SOURCE do
    # This task will be assigned dependencies dynamically, see the "plugins" stuff below.
    puts "Plugins done"
  end

  directory "#{BUILD}/var/run/couchdb"

  file COUCH_BIN => [COUCH_SOURCE, AUTOCONF_259, "#{BUILD}/var/run/couchdb"] do
    source = COUCH_SOURCE

    begin
      Dir.chdir(source) do
        # TODO: Use the built-in autoconf (with_autoconf '2.59') instead of depending on the system.
        cmd = "./bootstrap"
        cmd = "SED=`which sed` #{cmd}" if DISTRO[0] == :solaris
        sh cmd
      end

      Dir.mktmpdir 'couchdb-build' do |dir|
        Dir.chdir dir do
          show_file("config.log") do
            sh(configure_cmd(source, :prefix => true))
          end

          gmake
          gmake "check" if ENV['make_check']
          gmake "install"

          compress_beams "#{COUCH_BUILD}/lib/couchdb/erlang"

          if DISTRO[0] == :osx
            icu = Dir.glob("#{COUCH_BUILD}/lib/couchdb/erlang/lib/couch-*/priv/lib/couch_icu_driver.so").last
            js  = "#{COUCH_BUILD}/lib/couchdb/bin/couchjs"

            sh "install_name_tool -change libicuuc.44.dylib #{BUILD}/lib/libicuuc.44.dylib #{icu}"
            sh "install_name_tool -change libicui18n.44.dylib #{BUILD}/lib/libicui18n.44.dylib #{icu}"
            sh "install_name_tool -change ../lib/libicudata.44.0.dylib #{BUILD}/lib/libicudata.44.0.dylib #{icu}"

            sh "install_name_tool -change @executable_path/libmozjs.dylib #{BUILD}/lib/libmozjs.dylib #{js}"
          end
        end

        record_manifest 'couchdb'
      end
    ensure
      Dir.chdir(source) { sh "git ls-files --others --ignored --exclude-standard | xargs rm -vf" }
    end
  end

  # Determine what plugins are desired and have them built.
  plugins = (ENV['plugin'] || "") + "," + (ENV['plugins'] || "")
  plugins = plugins.split(',').select{|x| ! x.strip.empty? }

  unless plugins.empty?
    puts "Setting otp_keep=\"*\" for building plugins"
    ENV['otp_keep'] = '*'
  end

  plugins.each do |git_plugin|
    remote, commit = git_plugin.split
    plugin_mark = "#{COUCH_BUILD}/lib/build-couchdb/plugins/#{git_checkout_name remote}/#{commit}"

    task :plugins => plugin_mark
    file plugin_mark => 'environment:path' do
      source = git_checkout(git_plugin)
      Dir.chdir(source) do
        ENV['COUCH_SRC'] = "#{COUCH_SOURCE}/src/couchdb"
        gmake
      end
    end
  end

end

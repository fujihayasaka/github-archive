# typed: true
# frozen_string_literal: true

require "fileutils"
require "net/http"
require "open3"
require "serviceowners"
module GitHub
  class BonesExporter
    autoload :TestSuiteParser, "github/bones_exporter/test_suite_parser"

    include GitHub::ServiceMapping

    CODEOWNERS_KEY      = "codeowners"
    FILES_KEY           = "files"
    MAINTAINER_KEY      = "maintainer_team"
    PACKAGES_KEY        = "packages"
    REVIEWERS_KEY       = "reviewer_teams"
    SERVICE_CATALOG_KEY = "service_catalog"
    SERVICE_KEY         = "service"
    TABLEOWNERS_KEY     = "monolith_tables"
    SHA_KEY             = "sha"


    DISPLAY_WIDTH = 120
    JOB_NAME = "github-bones-data-export"
    ROOT_PACKAGE_NAME = "root"
    PACKAGE_REGEX = /^packages\/(\w+)\/package_todo.yml/

    # data structure that is saved to local yaml file
    #
    # sha: abc123
    # service_catalog: []
    # files:
    #  - <file_path>:
    #    codeowners: [<team_name>]
    #    maintainer_team: <team_name>
    #    reviewer_teams: [<team_name>]
    #    service: <service_name>
    #    test_suites: [<suite_constant>]
    # packages:
    #  - name: <package_name>
    #    service: <service_name>
    #    dependencies: [<package_name>]
    #    public_interface: true|false
    #    violations:
    #      <package_name>:
    #        <constant>:
    #          violations: [<violation_type>]
    #          files: [<file_path>]

    IGNORE_TEST_SUITE_FILES_REGEXP = [
      %r{test/test_helpers/},
      %r{test/factories/},
     ]

    attr_reader :list_mode, :output, :ci_mode

    def initialize(list_mode: false, include_test_suites: true, files: nil, ci_mode: false, output: StringIO.new)
      @list_mode = list_mode
      @output = output
      @ci_mode = ci_mode
      @include_test_suites = include_test_suites

      # only assign @files if there's anything, to allow lazy load in files method to work
      if files
        @files = Array(files).each do |file| # intentional to use each to return what was iterated, rather than map
          path = Pathname.new(file)
          raise "expected relative path for #{file}" unless path.relative?
          raise "missing file #{file}" unless path.exist?
        end
      end
    end

    def package_files
      return @package_files if defined?(@package_files)
      @package_files = serviceowners.paths.select { |f| f[PACKAGE_REGEX] }
      @package_files << "package_todo.yml"
    end

    def files
      return @files if defined?(@files)
      puts "Gathering files..." unless list_mode
      files = serviceowners.paths

      puts "Filtering files..." unless list_mode

      if limit
        files = files.to_a.sample(limit)
      end

      @files = files
    end

    def ignore_test_suite_regexp
      return @ignore_test_suite_regexp if defined?(@ignore_test_suite_regexp)
      @ignore_test_suite_regexp = Regexp.union(*IGNORE_TEST_SUITE_FILES_REGEXP)
    end

    def test_suite_files
      return @test_suite_files if defined?(@test_suite_files)
      @test_suite_files = safe_system("git grep -l Test test").lines.map(&:chomp)

      test_suite_files.reject! do |file|
        !file.end_with?(".rb") || file =~ ignore_test_suite_regexp
      end

      @test_suite_files
    end

    # An instance of the Codeowners::File class loaded with the CODEOWNERS doc
    def codeowners
      @codeowners ||= Codeowners::File.new(Rails.root.join("CODEOWNERS").read)
    end

    # The ownership.yaml doc loaded into a hash
    def durable_ownership
      return @durable_ownership if defined?(@durable_ownership)

      puts "Gathering service catalog data..."

      ownership_yaml_path = Rails.root.join("ownership.yaml")
      @durable_ownership = YAML.safe_load(ownership_yaml_path.read)
    end

    def packages
      puts "Gathering package data..."

      package_files.map do |package_file|
        package_data = {}

        package_name_for_file(package_file, package_data)
        service_for_file(package_file, package_data)
        package_public_interface(package_file, package_data)
        violations_for_package(package_file, package_data)
        metadata_for_package(package_file, package_data)

        package_data
      end
    end

    def tableowners
      return @tableowners if defined?(@tableowners)

      puts "Gathering tableowners data..."
      tableowners_yaml_path = GitHub::Serviceowners::Tableowners::TABLEOWNERS_YAML_PATH
      @tableowners = YAML.safe_load_file(tableowners_yaml_path)
    end

    # Iterates over each file and populates the maintainership data
    def files_maintainership
      file_data = {}

      puts "File count: #{files.length}"
      files.each_with_index do |file, index|
        print_files_progress(files.length, index)
        file_data[file] = maintainership_for_file(file)
      end

      file_data
    end

    # For a given file this creates and returns the maintainership hash
    #
    # returns
    # codeowners: [<string>]      The list of responsible teams gathered from the CODEOWNERS document
    # maintainer_team: <string>   The team that owns the file
    # reviewer_teams: [<string>]  The teams that are additional reviewers (interested parties) for the file
    # service: <string>           The service attributude to the file by service owners
    def maintainership_for_file(file)
      maintainership = {}

      maintainers_for_file(file, maintainership)
      service_for_file(file, maintainership)
      test_suite_for_file(file, maintainership)

      maintainership
    end

    def test_suite_for_file(file, data)
      return unless @include_test_suites && test_suite_files.include?(file)

      test_suites = TestSuiteParser.new(file).parse
      data["test_suites"] = test_suites if test_suites.present?
    end

    def maintainership_no_review_files
      return @no_review_files if defined?(@no_review_files)

      @no_review_files = []

      serviceowners = File.open("SERVICEOWNERS").read
      serviceowners.scan(GitHub::Serviceowners::NO_REVIEW_LINE_PATTERN).each { |line| @no_review_files << line.split.first }

      @no_review_files
    end

    # Gets all codeowners for a given file
    # Gets the maintainer and reviewers for a given file
    def maintainers_for_file(file, data)
      # If this is one of the maintainership files we don't generate CODEOWNERS
      # entries for: lie for Bones' sake by getting the codeowners for the
      # main serviceowners Ruby file.
      if maintainership_no_review_files.include?(file)
        file = GitHub::Serviceowners::SERVICEOWNERS_FILE
      end

      codeowner_teams = codeowners.for(file).keys.map(&:to_s)

      codeowner_teams.each do |owner|
        data[CODEOWNERS_KEY] ||= []
        data[CODEOWNERS_KEY].push(owner)
      end

      data[MAINTAINER_KEY], *data[REVIEWERS_KEY] = *codeowner_teams
    end

    # Gets the service for a given file
    def service_for_file(file, data)
      service = GitHub.serviceowners.service_for_path(file, prefix: true)
      data[SERVICE_KEY] = service.to_s unless service.nil?
    end

    # Gets the package name from a file path
    def package_name_for_file(file, data)
      return data["name"] = ROOT_PACKAGE_NAME if file == "package_todo.yml"
      name = file[PACKAGE_REGEX, 1]

      raise NameError, "Package name is nil" if name.nil?
      data["name"] = name.to_s
    end

    def package_public_interface(file, data)
      package_name = file[PACKAGE_REGEX, 1]
      data["public_interface"] = public_interface_path?(package_name)
    end

    def violations_for_package(file, data)
      raw_data = {}
      data["violations"] = raw_data

      return unless File.exist?(file)
      violation_data = YAML.safe_load(File.open(file))

      violation_data.each do |package_name, violations|
        package_name = ROOT_PACKAGE_NAME if package_name == "."
        package_name = clean_package_name(package_name)

        raw_data[package_name] = violations
      end
    end

    def metadata_for_package(file, data)
      file = file.gsub("package_todo.yml", "package.yml")
      package_data = YAML.safe_load(File.open(file))

      return unless package_data["dependencies"].present?
      data["dependencies"] = package_data["dependencies"].map { |d| clean_package_name(d) }
    end

    # collates all the data into a hash object
    #
    # returns
    # sha: <string>           The "snapshot" marker for dotcom
    # service_catalog: <hash> The raw data from the ownership.yaml file
    # package: <array>        Packages and package violations from the `package_todo.yml` files
    # files: <hash>           All the files on dotcom with their maintainership data
    def gather_data
      data = {}

      puts "Populating data with latest sha"
      data[SHA_KEY] = GitHub.current_sha

      puts "Populating data with ownership.yaml"
      data[SERVICE_CATALOG_KEY] = durable_ownership

      puts "Populating data with packages"
      data[PACKAGES_KEY] = packages

      puts "populating data with monolith file maintainership"
      data[FILES_KEY] = files_maintainership

      puts "populating data with tableowner.yaml"
      data[TABLEOWNERS_KEY] = tableowners

      puts "\nDone"

      data
    end

    def run!
      if list_mode
        files.each do |file|
          puts file
        end
        return
      end

      data = gather_data

      write_data_to_file(data)
      notify_bones_webhook if ci_mode

      0
    end

    private

    def serviceowners
      @serviceowners ||= ::Serviceowners::Main.new
    end

    # Normally for testing will limit the number of files exported
    def limit
      return @limit if defined?(@limit)
      @limit = if ENV["BONES_EXPORT_FILE_LIMIT"]
        ENV["BONES_EXPORT_FILE_LIMIT"].to_i
      end
    end

    # Removes the prefix 'packages' for package name
    def clean_package_name(name)
      name.gsub("packages/", "")
    end

    # The directory the local file will get written too
    def data_dir
      @data_dir ||= if ci_mode
        Pathname.new("/tmp/#{JOB_NAME}-artifacts")
      else
        Rails.root.join("tmp")
      end
    end

    # The full path including file name the local file will get written too
    def data_path
      @data_path ||= data_dir.join("ownership-data.yaml")
    end

    # Writes data to a local file to be uploaded to Octofactory
    def write_data_to_file(data)
      puts "Writing data to #{data_path}"
      data_dir.mkpath
      data_path.write(data.deep_stringify_keys.to_yaml)
    end

    # Pings the bones webhooke endpoint with the current SHA
    def notify_bones_webhook
      bones_url = ENV.fetch("BONES_URL", "https://bones.githubapp.com")
      # Parse the URL for the bones application
      uri = T.cast(URI.parse("#{bones_url}/maintainer_imports/webhook"), T.any(URI::HTTP, URI::HTTPS))
      puts
      puts "Hitting Bones endpoint #{uri}"

      # Create the request object
      # Set the authentication token
      header = { "Content-Type" => "text/json", "Authorization" => "Token token=#{hmac_token}" }
      # Send the current GitHub sha so that it knows the job has been run
      body = {
        sha: GitHub.current_sha,
        build_branch: ENV["BUILD_BRANCH"],
        build_url: ENV["BUILD_URL"],
      }

      # Create the request objects
      request = Net::HTTP::Post.new(uri.request_uri, header)
      request.body = body.to_json
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")

      # Send the request
      response = http.request(request)
      puts "Bones webhook response: #{response.code} #{response.msg}\n"
      puts "Response body:"
      puts response.body

      # Will raise an error if not 200
      # Artifacts will still be uploaded as per https://github.com/github/bp-buildrequest/pull/222
      response.error! if response.code != "200"
    end

    def puts(string = "")
      output.puts(string)
    end

    # In safe-ruby we cannot use backticks
    # As we need the stdout this runs the command a returns it
    def safe_system(command)
      stdout_str, error_str, status = Open3.capture3(command)
      if status.success?
        stdout_str
      else
        puts error_str
        puts stdout_str
        raise "'#{command}' failed with status #{status}"
      end
    end

    # Just for fun, prints a progress bar
    def print_percentage(total, current)
      # Only print out every 100 files or on final file
      if current % 100 == 0 || current == total
        x = (current * (100.to_f / total)).round(2)
        bar = "#{current}/#{total}:<#{"=" * x}#{"-" * (100 - x)}> #{x.round(2)}%"

        output.putc "\r"
        output.print bar
        output.flush
      end
    end

    # Prints a nice output
    def print_files_progress(total, current)
      # Current is a index so file 0 is file 1
      current += 1

      if @ci_mode
        output.putc "."
        # add a newline break periodically to display nicer on CI
        # without it, they will all be on one file
        output.putc "\n" if current % DISPLAY_WIDTH == 0
      else
        print_percentage(total, current)
      end
    end

    def public_interface_path?(package_name)
      package_file = "packages/#{package_name}/package.yml"
      return false unless File.exist?(package_file)

      package_file_data = YAML.load_file(package_file)
      public_path_folder = if package_file_data.include?("public_path")
        "packages/#{package_name}/#{package_file_data["public_path"]}"
      else
        "packages/#{package_name}/app/public"
      end
      return false unless File.exist?(public_path_folder)

      public_files = Dir.glob("#{public_path_folder}/**/*.rb")
      return false if public_files.empty?

      true
    end

    def hmac_token
      return "" if GitHub.bones_hmac_key.blank?
      timestamp = Time.now.to_i.to_s
      digest = OpenSSL::Digest::SHA256.new
      hmac = OpenSSL::HMAC.new(GitHub.bones_hmac_key, digest)
      hmac << timestamp
      "#{timestamp}.#{hmac}"
    end
  end
end

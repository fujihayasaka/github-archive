module Enterprise
  module Crypto
    # An update package which contains chef cookbooks and debian packages.
    # Packages are versioned and architecture specific.
    #
    class Package < Struct.new(:version, :cookbooks, :roles, :code_debs,
                               :package_debs, :package_gz, :support_script,
                               :architecture)
      include SafeDir
      include Tar

      # Extracts an update package into the provided path.
      #
      # package_path  - the path to the update package.
      # output_path   - the path to the extracted package contents.
      #
      # Returns the metadata Hash or raises an error.
      def self.extract(package_path, output_path, vault = Crypto.package_vault)
        tar_file = Crypto.with_vault(vault) do
          vault.read_package(File.open(package_path))
        end

        from_tar(tar_file.path, output_path)

        verify_extraction(output_path)
      rescue => e
        abort_extract(output_path)

        raise e
      ensure
        File.delete(tar_file) if tar_file
      end

      # Checks that a Package was extracted properly. Raises an exception
      # if something went wrong.
      #
      # Returns the metadata Hash or raises an error.
      def self.verify_extraction(output_path)
        metadata_file = File.join(output_path, 'metadata.json')

        unless File.exist?(metadata_file)
          raise(Error, "metadata.json file missing at #{metadata_file}.")
        end

        metadata = JSON.parse(File.read(metadata_file))

        raise(Error, "Package is missing checksums.") if metadata['checksum'].nil?

        metadata['checksum'].each do |path, checksum|
          verify_checksum(File.join(output_path, path), checksum)
        end

        execute_support_script(File.join(output_path, 'support_script'))

        metadata
      end

      # Removes all Package files when an extract fails.
      def self.abort_extract(output_path)
        FileUtils.rm_r(output_path)
      end

      def self.verify_checksum(file, expected)
        actual = Digest::MD5.file(file).hexdigest

        unless expected == actual
          raise(Error, "Checksum mismatch on #{file}. Expected '#{expected}' but got '#{actual}'.")
        end
      end

      def self.execute_support_script(path)
        return unless File.exist?(path)

        system(path)
      end

      def metadata
        {
          'version'       => version,
          'checksum'      => checksums,
          'architecture'  => architecture || 'i386',
        }
      end

      # Compiles this update package to a file.
      #
      # path  - the file path to the package output.
      #
      def to_ghp(path = default_package_path, vault = Crypto.package_vault, tmp_dir = mktmpdir.to_path)
        secure_tmp_path = File.join(mktmpdir, SecureRandom.hex)
        tar = to_tar(to_dir(tmp_dir), secure_tmp_path)

        File.open(path, 'wb') do |f|
          Crypto.with_vault(vault) do
            f << vault.generate_package(tar)
          end
        end

      ensure
        FileUtils.rm_rf(secure_tmp_path)
      end

      def checksums
        sums = {}

        unless code_debs.nil?
          code_debs.each do |file|
            sums[File.join('code_debs', File.basename(file))] = md5(file)
          end
        end

        unless package_debs.nil?
          package_debs.each do |file|
            sums[File.join('package_debs', File.basename(file))] = md5(file)
          end
        end

        sums
      end

      def md5(file)
        Digest::MD5.file(file).hexdigest
      end

      def to_dir(dir = mktmpdir.to_path)
        write(File.join(dir, 'metadata.json'), metadata.to_json)
        write(File.join(dir, 'Package.gz'), package_gz, 'b') unless package_gz.nil?
        write(File.join(dir, 'support_script'), support_script, '', 0700) unless support_script.nil?

        unless cookbooks.nil?
          FileUtils.cp_r(cookbooks, dir)
          cleanup_cookbooks(dir)
        end

        FileUtils.cp_r(roles, dir)                          if     !roles.nil? && File.directory?(roles)
        copy(File.join(dir, 'code_debs'), code_debs)        unless code_debs.nil?
        copy(File.join(dir, 'package_debs'), package_debs)  unless package_debs.nil?

        dir
      end

      def write(file, data, encoding = '', mode = nil)
        File.open(file, "w#{encoding}") do |f|
          f << data
        end

        File.chmod(mode, file) if mode
      end

      def default_package_path
        "github-enterprise-#{version}.ghp"
      end

      def copy(dir, files)
        FileUtils.mkdir_p(dir)

        files.each do |file|
          FileUtils.cp(file, dir)
        end
      end

      def cleanup_cookbooks(dir)
        Dir.glob(File.join(dir, 'cookbooks', '**', '*id_{r,d}sa{,.pub}')).each do |keyfile|
          FileUtils.rm(keyfile)
        end
      end
    end
  end
end

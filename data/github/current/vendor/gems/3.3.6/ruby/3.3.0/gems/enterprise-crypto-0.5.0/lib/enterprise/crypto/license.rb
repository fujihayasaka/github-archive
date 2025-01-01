module Enterprise
  module Crypto
    # An enterprise install license. Contains metadata about the
    # enterprise install (such as the customer license, seat count, etc.)
    # and an open set of files that are overlayed on the enterprise
    # VM instance.
    #
    class License < Struct.new(:customer, :metadata, :files)
      extend SafeDir
      include Tar

      # Creates a new license for the customer.
      #
      # customer    - a Customer object which represents the enterprise customer.
      # seats       - an Integer of the total customer seat count.
      # expire_at   - a DateTime of when the license expires.
      # support_key - an optional public rsa/dsa key for SSH access.
      # metadata    - a Hash of extra data that describes the license.
      # files       - an optional set of files to be placed on the VM.
      #
      def self.generate(customer, seats, expire_at, support_key = nil, extra_metadata = {}, files = {})
        metadata = extra_metadata.inject({}) {|h, (k,v)| h.update(k.to_s => v) }

        license = new(customer, metadata, files)

        license.company               = customer.name
        license.seats                 = seats
        license.expire_at             = expire_at
        license.customer_private_key  = customer.secret_key_data
        license.customer_public_key   = customer.public_key_data
        license.support_key           = support_key unless support_key.nil?

        license
      end

      # Reads and loads a license from raw license data.
      #
      # asc_data  - the encrypted & signed license data.
      #
      def self.load(asc_data, vault = Crypto.license_vault, tmp = mktmpdir.to_path)
        tar_file = Crypto.with_vault(vault) do
          vault.read_license(asc_data)
        end

        if from_tar(tar_file.path, tmp)
          from_dir(tmp)
        else
          raise Error.new("Tar failed to extract: #{tar_file} to #{tmp}")
        end
      ensure
        # Remove the extration directory.
        # We don't need it around for anything.
        File.delete(tar_file) if tar_file
        FileUtils.rm_rf tmp
      end

      # Serializes this license to binary data.
      #
      def to_bin(vault = Crypto.license_vault)
        lic_dir = to_dir
        lic_tar = to_tar(lic_dir)
        Crypto.with_vault(vault) do
          vault.generate_license(lic_tar)
        end
      ensure
        FileUtils.rm_rf lic_tar
        FileUtils.rm_rf lic_dir
        FileUtils.rm_rf tmpdir
      end

      def company
        metadata['company']
      end

      def company=(c)
        metadata['company'] = c
      end

      def seats
        metadata['seats']
      end

      def seats=(count)
        metadata['seats'] = count.to_i
      end

      def learning_lab_seats
        metadata['learning_lab_seats']
      end

      def learning_lab_seats=(count)
        metadata['learning_lab_seats'] = count.to_i
      end

      def learning_lab_evaluation_expires
        metadata['learning_lab_evaluation_expires']
      end

      def learning_lab_evaluation_expires=(date)
        date ||= expire_at
        metadata['learning_lab_evaluation_expires'] = date
      end

      def evaluation
        !!metadata['evaluation']
      end
      alias evaluation? evaluation

      def evaluation=(value)
        metadata['evaluation'] = value
      end

      def expire_at
        DateTime.parse(metadata['expire_at'])
      end

      def expire_at=(time)
        metadata['expire_at'] = DateTime.parse(time.to_s).to_s
      end

      def customer_public_key
        metadata['customer_public_key']
      end

      def customer_public_key=(value)
        metadata['customer_public_key'] = value
      end

      def customer_private_key
        metadata['customer_private_key']
      end

      def customer_private_key=(value)
        metadata['customer_private_key'] = value
      end

      def support_key
        metadata['support_key']
      end

      def support_key=(value)
        metadata['support_key'] = value
      end

      def perpetual
        !!metadata['perpetual']
      end
      alias perpetual? perpetual

      def perpetual=(value)
        metadata['perpetual'] = value
      end

      def unlimited_seating
        !!metadata['unlimited_seating']
      end
      alias unlimited_seating? unlimited_seating

      def unlimited_seating=(value)
        metadata['unlimited_seating'] = value
      end

      def ssh_allowed
        !!metadata['ssh_allowed']
      end
      alias ssh_allowed? ssh_allowed

      def ssh_allowed=(value)
        metadata['ssh_allowed'] = value
      end

      def cluster_support
        !!metadata['cluster_support']
      end
      alias cluster_support? cluster_support

      def cluster_support=(value)
        metadata['cluster_support'] = value
      end

      def croquet_support
        !!metadata['croquet_support']
      end
      alias croquet_support? croquet_support

      def croquet_support=(value)
        metadata['croquet_support'] = value
      end

      def custom_terms
        !!metadata['custom_terms']
      end
      alias custom_terms? custom_terms

      def custom_terms=(value)
        metadata['custom_terms'] = value
      end

      def insights_enabled
        !!metadata['insights_enabled']
      end
      alias insights_enabled? insights_enabled

      def insights_enabled=(value)
        metadata['insights_enabled'] = value
      end

      def insights_expire_at
        return metadata['insights_expire_at'] if insights_enabled?
        nil
      end

      def insights_expire_at=(date)
        date ||= expire_at
        metadata['insights_expire_at'] = date
      end

      def advanced_security_enabled
        !!metadata['advanced_security_enabled']
      end
      alias advanced_security_enabled? advanced_security_enabled

      def advanced_security_enabled=(value)
        metadata['advanced_security_enabled'] = value
      end

      def advanced_security_seats
        metadata['advanced_security_seats']
      end

      def advanced_security_seats=(count)
        metadata['advanced_security_seats'] = count.to_i
      end

      def metered
        !!metadata['metered']
      end
      alias metered? metered

      def metered=(value)
        metadata['metered'] = value
      end

      def self.from_dir(dir)
        license, public_data, secret_data = new, nil, nil

        Dir[File.join(dir, '**', '*')].each do |file|
          case file.sub(dir, '').sub(/^\//, '')
          when 'metadata.json'    then license.metadata = JSON.parse(File.read(file, :mode => 'rb'))
          when 'gpg/pubring.gpg'  then public_data = File.read(file, :mode => 'rb')
          when 'gpg/secring.gpg'  then secret_data = File.read(file, :mode => 'rb')
          when %r{^extra/.+}      then license.files[file[%r{^#{dir}\/extra/(.*)$}, 1]] = File.read(file, :mode => 'rb')
          end
        end

        license.customer = Customer.from(secret_data, public_data)

        license
      end


      def to_dir(dir = mktmpdir.to_path)
        File.open(File.join(dir, 'metadata.json'), 'wb') {|f| f << metadata.to_json }

        FileUtils.mkdir_p(File.join(dir, 'gpg'))
        File.open(File.join(dir, 'gpg', 'secring.gpg'), 'wb') {|f| f << customer.secret_key_data }
        File.open(File.join(dir, 'gpg', 'pubring.gpg'), 'wb') {|f| f << customer.public_key_data }


        files.each do |name, data|
          FileUtils.mkdir_p(File.join(dir, 'extra', File.dirname(name)))
          File.open(File.join(dir, 'extra', name), 'wb') {|f| f << data }
        end

        dir
      end
    end
  end
end

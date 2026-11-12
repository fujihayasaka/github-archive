module Maven

  # Package release class that will be serialized to be sent to
  # the sink.
  # At the moment we only send the package info, eventually we
  # should also send the dependencies of the package.
  class PackageRelease
    def initialize(record, sink_address: "")
      @sink_address = sink_address
      group_id = record.get(Record::GROUP_ID)
      artifact_id = record.get(Record::ARTIFACT_ID)
      package_name =  "#{group_id}:#{artifact_id}"
      package_version = record.get(Record::VERSION)
      home_url = record.get(Record::OSGI_EXPORT_DOCURL)

      record_modified = record.get(Record::REC_MODIFIED)
      # Divide record_modified by 1000 because the Java timestamp is in milliseconds
      published_at = record_modified / 1000 if record_modified

      @struct = Struct.new(:package_manager, :package_name, :package_version, :home_url, :published_at).new(:maven, package_name, package_version, home_url, published_at)
    end

    def to_h
      @struct.to_h
    end

    def to_json(options = nil)
      to_h.to_json(options)
    end

    def fjord_hash
      {
        cluster: @sink_address.include?("docker") ? "localhost" : nil,
        schema: "hydro.schemas.github.dependencygraph.v0.PackageRelease",
        value: to_h.reject { |key, value| value.to_s.empty? }.to_json,
      }
    end
  end
end

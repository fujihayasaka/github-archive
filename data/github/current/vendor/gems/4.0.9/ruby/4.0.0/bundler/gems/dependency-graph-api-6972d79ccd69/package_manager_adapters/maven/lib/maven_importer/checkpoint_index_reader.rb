require_relative "../logging"

module Maven
  class CheckpointIndexReader < org.apache.maven.index.reader.IndexReader
    include Logging

    def initialize(sink, local, remote)
      @remote = remote
      props = properties(remote)
      index_id = props.get_property("nexus.index.id")

      @checkpoint = sink.checkpoint(index_id)
      checkpoint_value = @checkpoint.value
      last_incremental = props.get_property("nexus.index.last-incremental").to_i
      @skip = checkpoint_value > last_incremental
      if @skip
        logger.info "Checkpoint #{index_id} is #{checkpoint_value}, last incremental is #{last_incremental}. Skipping updates."
      elsif checkpoint_value != 0
        logger.info "Checkpoint #{index_id} is #{checkpoint_value}"
        props.set_property("nexus.index.last-incremental", checkpoint_value.to_s)
        file = File.open(local.root_path.join("nexus-maven-repository-index.properties"), "w")
        org.apache.maven.index.reader.Utils.storeProperties(file.to_outputstream, props)
        file.close
      end

      super(local, remote)
    end

    def close
      if @skip
        return
      end
      last_increment = properties(@remote).get_property("nexus.index.last-incremental")
      @checkpoint.set(last_increment)
      index_name = properties(@remote).get_property("nexus.index.id")
      logger.info "Checkpoint #{index_name} set to #{last_increment}"
      super
    end

    def getChunkNames # rubocop:disable Naming/MethodName
      if @skip
        return [].to_java(:string)
      end
      super
    end

    def each(&blk)
      if @skip
        return []
      end
      super(&blk)
    end

    def properties(remote)
      props_file = remote.locate("nexus-maven-repository-index.properties")
      org.apache.maven.index.reader.Utils.loadProperties(props_file)
    end
  end
end

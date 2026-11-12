module Ingest
  module Blocklist
    VALID_LIST_TYPES = %w(manifest_repos packages)
    INTERVAL = 11
    @last_refreshed = { manifest_repos: Time.at(0), packages: Time.at(0) }
    @blocklists = { manifest_repos: [], packages: [] }

    class << self
      def view(type:)
        if VALID_LIST_TYPES.include?(type.to_s)
          return get_list(type: type)
        else
          return
        end
      end

      def add(type:, item:)
        if VALID_LIST_TYPES.include?(type.to_s)
          get_list(type: type)
          add_to(type: type, value: item)
        else
          return
        end
      end

      def remove(type:, item:)
        if VALID_LIST_TYPES.include?(type.to_s)
          get_list(type: type)
          remove_from(type: type, value: item)
        else
          return
        end
      end

      def clear(type:)
        clear_list(type: type)
      end

      def blocklisted_manifest?(manifest)
        id = manifest.is_a?(Hash) ? manifest[:github_repository_id] : manifest&.github_repository_id
        nwo = manifest.is_a?(Hash) ? manifest[:repository_nwo] : manifest&.repository_nwo
        blocklist = get_list(type: :manifest_repos)
        blocklist.include?(id.to_s) || blocklist.include?(nwo)
      end

      def blocklisted_package?(package)
        get_list(type: :packages).include?("#{package.package_name}:#{package.package_manager.human_name.downcase}")
      end

      private

      def kv
        GitHub::KV.new { ActiveRecord::Base.connection }
      end

      def blocklist_name(type:)
        "#{type}_blocklist"
      end

      def clear_list(type:)
        kv.del(blocklist_name(type: type))
        @blocklists[type] = []
      end

      def get_list(type:)
        return [] unless VALID_LIST_TYPES.include?(type.to_s)
        if Time.now > (@last_refreshed[type] + INTERVAL)
          kv_list = begin
                      kv.get(blocklist_name(type: type)).value!
                    rescue => e
                      Failbot.report(e)
                      raise e
                    end
          @blocklists[type] = kv_list.split(",") unless kv_list.nil? # because GitHub::KV.get returns a GitHub::Result that can be nil
          @last_refreshed[type] = Time.now
        end
        return @blocklists[type]
      end

      def add_to(type:, value:)
        return unless VALID_LIST_TYPES.include?(type.to_s)
        @blocklists[type].push(value)
        kv.set(blocklist_name(type: type), @blocklists[type].join(","))
      end

      def remove_from(type:, value:)
        return unless VALID_LIST_TYPES.include?(type.to_s)
        @blocklists[type].delete(value)
        kv.set(blocklist_name(type: type), @blocklists[type].join(","))
      end
    end
  end
end

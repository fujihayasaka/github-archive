# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class CaseInsensitiveHash < Hash
      def [](key)
        super(key.downcase) unless key.nil?
      end

      def []=(key, value)
        super(key.downcase, value) unless key.nil? || value.nil?
      end
    end
  end
end

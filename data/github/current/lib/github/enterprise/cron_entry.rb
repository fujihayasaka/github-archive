# typed: true
# frozen_string_literal: true

module GitHub
  module Enterprise

    # Vendorized version of CronEntry extracted from github.com/priit/cronedit.
    class CronEntry
      DEFAULTS = {
          minute: "*",
          hour: "*",
          day: "*",
          month: "*",
          weekday: "*",
          command: "",
      }

      class FormatError < StandardError; end

      # Hash def, or raw String def
      def initialize(aDef = {})
        if aDef.kind_of? Hash
          wrong = aDef.collect { |k, _v| DEFAULTS.include?(k) ? nil : k }.compact
          raise "Wrong definition, invalid constructs #{wrong}" unless wrong.empty?
          @defHash = DEFAULTS.merge aDef
          # TODO: validate values
          @def = to_raw @defHash
        else
          @defHash = parseTextDef aDef
          @def = aDef
        end
      end

      def to_s
        @def.freeze
      end

      def to_hash
        @defHash.freeze
      end

      def [](aField)
        @defHash[aField]
      end

      def to_raw(aHash = nil)
        aHash ||= @defHash
        "#{aHash[:minute]}\t#{aHash[:hour]}\t#{aHash[:day]}\t#{aHash[:month]}\t" +
            "#{aHash[:weekday]}\t#{aHash[:command]}"
      end

      private

      # Parses a raw text definition of crontab entry
      # returns hash definition
      # Original author of parsing: gotoken@notwork.org
      def parseTextDef(aLine)
        hashDef = parse_timedate aLine
        hashDef[:command] = aLine.scan(/(?:\S+\s+){5}(.*)/).shift[-1]
        ##TODO: raise( FormatError.new "Command cannot be empty") if aDef[:command].empty?
        hashDef
      end

      # Original author of parsing: gotoken@notwork.org
      def parse_timedate(str, aDefHash = {})
        minute, hour, day_of_month, month, day_of_week =
            str.scan(/^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/).shift
        day_of_week = day_of_week.downcase.gsub(/#{WDAY.join("|")}/) do
          WDAY.index($&)
        end
        aDefHash[:minute] = parse_field(minute,       0, 59)
        aDefHash[:hour] = parse_field(hour,         0, 23)
        aDefHash[:day] = parse_field(day_of_month, 1, 31)
        aDefHash[:month] = parse_field(month,        1, 12)
        aDefHash[:weekday] = parse_field(day_of_week,  0, 6)
        aDefHash
      end

      # Original author of parsing: gotoken@notwork.org
      def parse_field(str, first, last)
        list = str.split(",")
        list.map! do |r|
          r, every = r.split("/")
          every = every ? every.to_i : 1
          f, l = r.split("-")
          range = if f == "*"
            first..last
          elsif l.nil?
            f.to_i..f.to_i
          elsif f.to_i < first
            raise FormatError.new("out of range (#{f} for #{first})")
          elsif last < l.to_i
            raise FormatError.new("out of range (#{l} for #{last})")
          else
            f.to_i..l.to_i
          end
          range.to_a.find_all { |i| (i - first) % every == 0 }
        end
        list.flatten!
        list.join ","
      end

      WDAY = %w(sun mon tue wed thu fri sut)
    end
  end
end

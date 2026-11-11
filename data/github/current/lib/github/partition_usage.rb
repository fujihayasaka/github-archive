# typed: false
# frozen_string_literal: true

module GitHub
  module PartitionUsage
    PartitionInfo = Struct.new(:mountpoint, :used, :free) do
      def total
        free + used
      end

      def percent
        used / total.to_f * 100
      end

      def partition
        mountpoint.split("/").last
      end
    end

    extend self

    def df(mountpoints)
      output = Progeny::Command.new("/bin/df", "-Pk", "--", *mountpoints).out

      mountpoints.zip(output.lines.drop(1)).map do |mountpoint, line|
        info = line.split

        PartitionInfo.new(mountpoint, info[2].to_i, info[3].to_i)
      end
    end

    def df_i(mountpoints)
      output = Progeny::Command.new("/bin/df", "-Pi", "--", *mountpoints).out

      mountpoints.zip(output.lines.drop(1)).map do |mountpoint, line|
        info = line.split

        PartitionInfo.new(mountpoint, info[2].to_i, info[3].to_i)
      end
    end
  end
end

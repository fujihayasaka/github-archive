require "open3"

module OneOffImporters
  # Go is a one-off importer for Go modules.
  # For an overview, see "Go module support in Dependency Graph", ../../docs/go-modules.md.
  class Go < Base
    def run
      # All the work is done by the external gooneoff command.
      #
      # In production, the value of $FJORD_URL comes from Vault.
      out, err, status = Open3.capture3(
                  "./gooneoff", "-fjord_url=" + ENV["FJORD_URL"], "--", package_name)
      if status != 0
        raise "gooneoff failed: #{err}"
      end
      STDERR.puts "gooneoff #{package_name} succeeded: <<#{err}>>"
    end
  end
end

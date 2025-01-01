# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    ATTRIBUTE_LOAD_FLAGS = Rugged::Repository::Attributes.parse_opts(
                             :skip_system => true,
                             :priority => [:index]
                           )
    GITATTRIBUTES        = ".gitattributes".freeze

    rpc_reader :read_attributes
    def read_attributes(tree_oid, paths, keys = nil)
      ensure_valid_full_oid(tree_oid)

      paths = paths.compact

      return [] if paths.size == 0
      return [{}] if keys != nil && keys.size == 0

      args = ["--stdin", "-z", "--source", "#{tree_oid}^{tree}"]
      if keys != nil
        keys.each do |key|
          raise GitRPC::InvalidObject, "Invalid attribute name #{key}" unless key =~ /\A(?!-)[0-9A-Za-z_\.-]*\z/
        end
        args += keys
      else
        args << "-a"
      end

      res = spawn_git(
        "check-attr",
        args,
        paths.join("\0".b))

      if res["ok"]
        result = res["out"].split("\0")

        attributes = Hash.new
        result.each_slice(3).map do |path, attribute, info|
          attributes[path] = Hash.new if attributes[path].nil?
          attributes[path][attribute] = case info
          when "unspecified"
            nil
          when "set"
            true
          when "unset"
            false
          else
            # If an attribute is set to the empty value and it's the last element in the check-attr output,
            # the "split" process removes the trailing empty string from the resulting array.
            # While processing the elements 3 by 3, the info element will be null in the scenario described before.
            info.nil? ? "" : info
          end
        end
        attributes.values
      elsif res["err"] =~ /not a valid tree-ish source/
        raise GitRPC::InvalidObject, "Invalid tree oid #{tree_oid}"
      elsif res["err"] =~ /error: No attribute specified/
        raise GitRPC::InvalidObject, "No attribute specified: tree_oid: #{tree_oid}"
      end
    end
  end
end

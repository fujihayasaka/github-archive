# rubocop:disable Style/FrozenStringLiteralComment
module GitRPC
  class Backend
    TREE_ENTRY_SIZE_LIMIT = 10 * 1024 * 1024
    TREE_ENTRY_TRUNCATION_SIZE = 1024 * 1024
    TREE_ENTRY_TRUNCATE_LIMIT = 1024 * 1024

    # Public: read a single tree entry given a path and a sha.
    #
    # oid - the oid of the commit or tree to find the entry in.
    # path - The path of the blob or tree to look for.
    #
    # See Client#read_tree_entry for usage.
    rpc_reader :read_tree_entry
    def read_tree_entry(oid, path = nil, options = {})
      truncate = if options.key?("truncate")
        options["truncate"]
      else
        TREE_ENTRY_TRUNCATION_SIZE
      end
      limit = if options.key?("limit")
        options["limit"]
      else
        TREE_ENTRY_SIZE_LIMIT
      end

      type = if options.key?("type")
        options["type"]
      end

      reader = ObjectReader.new(native, limit: limit)

      # Check if the object exists, otherwise raise an error
      revision_info, submodule_info = get_info(oid, path, reader, type)

      return submodule_info if !submodule_info.empty?

      # At this point we know we have a valid revision and path
      # and the latter doesn't point to a submodule
      revision_data = transform_symbols(reader.object("#{oid}:#{path}", :contents))

      result = if path.nil? || path.empty? || revision_info["type"] == "tree"
        get_tree_result(revision_data, type, path)
      else
        get_object_result(oid, revision_data, path, type, truncate, limit, options.merge(
          {
            :resolve_symlink => true,
            :full_blob => true,
          })
        )
      end
    ensure
      reader&.close
    end

    def transform_symbols(data)
      transformed = stringify_keys(data)
      transformed["type"] = data[:type].to_s

      transformed
    end

    def normalize_path(path, data)
      pathname = File.split(data)
      link_pathname = File.split(path)
      name = pathname[1]

      base = File.join("/", link_pathname[0] != "." ? link_pathname[0] : "")
      full_path = File.expand_path(data, base).sub(/\A\/+/, "")
      path = full_path

      [name.b, path.b]
    end

    def is_submodule?(oid, path)
      submodules = read_submodules(oid)
      (submodules.empty? || submodules.find { |s| s["path"] == path }.nil?) ? false : true
    end

    def get_submodule_result(oid, path, type)
      return {} unless is_submodule?(oid, path)
      res = spawn_git("show-paths", ["-z", oid], path)
      if res["ok"] && res["out"] != ""
        header, body = parse_output(res["out"])

        check_type(header[1], type, path)

        if path != header[3]
          return {}
        end

        {
          "type" => header[1],
          "oid" => header[2],
          "mode" => header[0].to_i(8),
          "name" => path,
          "path" => path,
          "size" => nil,
          "content" => nil,
        }
      else
        {}
      end
    end

    def get_tree_result(data, type, path)
      actual_type = data["type"]
      check_type(actual_type, type, path)

      oid = if actual_type == "tree"
        data["oid"]
      elsif actual_type == "commit"
        data["data"].split("\n")[0].split(" ")[1]
      else
        raise GitRPC::InvalidObject, "Invalid object type #{type}, expected commit or tree"
      end

      result = {
        "type" => "tree",
        "oid"  => oid,
        "mode" => 040000,
        "size" => nil,
      }

      if path != nil && !path.empty?
        result["name"] = path
        result["path"] = path.delete_suffix("/")
      else
        result["name"] = ""
        result["path"] = ""
      end

      result
    end

    def check_type(actual_type, type, path)
      if type && type != actual_type
        raise GitRPC::InvalidObject, "Invalid type at path: #{path}, expected #{type}, got #{actual_type}"
      end
    end

    def parse_output(output)
      index = output.index("\0")
      header = output[0..index - 1].split(" ")
      body = output[index + 1..-1]
      [header, body]
    end

    def get_object_result(oid, data, path, type, truncate, limit, opts)
      object = data["oid"]
      actual_type = data["type"]
      size = data["size"]
      mode = data["filemode"]
      res = {
        "type" => actual_type,
        "oid"  => object,
        "mode" => mode,
        "name" => path,
        "path" => path.delete_suffix("/"),
        "size" => nil,
      }

      check_type(actual_type, type, path)

      if actual_type == "blob"
        if symlink?(mode) && opts[:resolve_symlink]
          result = {}
          target = {}

          symlink_reader = build_symlink_reader(limit)

          target_data = follow_symlinks(symlink_reader, oid, path, limit, :contents)

          if target_data["type"] == "blob"
            target = target.merge(
              get_object_result(object, target_data, path, "blob", truncate, limit, { :resolve_symlink => false, :full_blob => false, :skip_size => opts[:skip_size] })
            )
          elsif target_data["type"] == "tree"
            target = target.merge(get_tree_result(target_data, "tree", path))
          elsif target_data["type"] == "dangling"
            target = target.merge(get_dangling_symlink(target_data))
          elsif target_data["type"] == "external_symlink"
            target = target.merge(get_external_symlink(target_data))
          end

          if data["data"].nil?
            # This means that the original `object_reader` operation has reached the limit. However, we do  need to
            # resolve the symlink target, so we need to re-fetch the data
            reload_reader = ObjectReader.new(native)
            data = transform_symbols(reload_reader.object("#{oid}:#{path}", :contents))
            reload_reader.close
          end

          n, p = normalize_path(path, data["data"])
          target["name"] = n
          target["path"] = p

          if is_valid_symlink(target_data)
            res["symlink_target"] = target["oid"]
            res["symlink_target_object"] = target
          end
        end

        if !opts[:skip_size] || opts[:full_blob]
          if opts[:full_blob]
            res.merge!(get_blob(data, size, truncate, limit))
          else
            res.merge!("size" => size)
          end
        end
      end

      res
    ensure
      symlink_reader&.close
    end

    def is_valid_symlink(symlink_info)
      !%w(dangling external_symlink).include?(symlink_info["type"])
    end

    def follow_symlinks(reader, oid, path, limit, command)
      transform_symbols(reader.object("#{oid}:#{path}", command))
    end

    def build_symlink_reader(limit)
      ObjectReader.new(
        native,
        git_opts = ["-c", "core.maxsymlinkdepth=2", "-c", "core.symlinkresolutionmode=best-effort"],
        limit: limit,
        follow_symlinks: true)
    end

    def get_dangling_symlink(data)
      b = data["data"].split(":")[1].strip
      {
        "data": b,
        "content": b,
      }
    end

    def get_external_symlink(data)
      {
        "size": data["size"],
        "data": data["data"],
      }
    end

    def get_blob(data, size, truncate, limit)
      blob_hash = {
        "size" => size,
        "data" => "",
        "truncated" => false,
        "size_over_limit" => false
      }

      if limit && size > limit
        blob_hash["truncated"] = true
        blob_hash["size_over_limit"] = true
      else
        content = if truncate && size > truncate
          blob_hash["truncated"] = true
          data["data"] = data["data"][0...truncate]
        else
          data["data"]
        end
        blob_hash["data"] = content
        blob_hash["oid"] = data["oid"]
        blob_hash["encoding"] = GitRPC::Encoding.guess_and_tag(content)
        blob_hash["binary"] = blob_hash["encoding"].nil?
      end

      blob_hash
    end

    private

    def get_info(oid, path, reader, type)
      # Check if the object exists, otherwise raise an error
      oid_info = reader.object(oid, :info)
      if oid_info[:type].nil?
        raise GitRPC::ObjectMissing, "object not found - no match for id (#{oid})"
      elsif oid_info[:type] == :tag || oid_info[:type] == :blob
        # Raise the same exception as the original code if the type is not a tree or commit
        # In the case of the tag we could follow the tag to the commit and then the tree (cat-file already does it),
        # but for now I will raise the same exception
        raise GitRPC::InvalidObject, "Invalid object type #{oid_info[:type]}, expected commit or tree"
      end

      # Check if the path exists
      revision_info = reader.object("#{oid}:#{path}", :info)
      result = if revision_info.nil? || revision_info[:type].nil?
        # If the path does not exist, we should raise a NoSuchPath error
        # but first we should check if there is a submodule at the
        # indicated path
        result = get_submodule_result(oid, path, type)
        return [{}, result] if !result.empty?

        raise GitRPC::NoSuchPath, "the path '#{path}' does not exist in the given tree"
      end

      [revision_info, {}]
    end

    def fetch_tree(oid)
      obj = rugged.lookup(oid)
      case obj.type.to_sym
      when :commit
        obj.tree
      when :tree
        obj
      else
        raise GitRPC::InvalidObject, "Invalid object type #{obj.type}, expected commit or tree"
      end
    end

    def resolve_symlink(entry, path, root)
      resolved = rugged.read(entry[:oid]).data.strip
      base = File.join("/", path)
      dest = File.expand_path(resolved, base).sub(/\A\/+/, "")

      target = root.path(dest)
      [dest, target] if [:blob, :tree].include?(target[:type])
    rescue
      nil
    end

    def symlink?(mode)
      mode & 0120000 == 0120000
    end

    def read_entries_from_data(data)
      contents = data.chomp("\0")
      entries = []

      while !contents.nil? && pos = contents.index("\0") do
        object_info = contents[0...pos]
        entry_finish = pos + hash_algo.bytesize
        object_oid = contents[pos + 1..entry_finish]
        mode, name = object_info.split(" ")
        # We only care about trees so I am not properly setting the type for all the other entries
        entries << { "name" => name, "oid" => object_oid.unpack("H*")[0], "type" => mode == "40000" ? :tree : nil }

        contents = contents[entry_finish + 1..-1]
      end

      entries
    end

    def flatten_entry_path_git(entry)
      reader = ObjectReader.new(native)
      path = nil

      loop do
        entry_data = reader.object(entry["oid"], :contents)
        tree_entries = read_entries_from_data(entry_data[:data])
        break if tree_entries.size != 1

        entry = tree_entries[0]
        break if entry["type"] != :tree
        path = File.join(path || "", entry["name"].b)
      end

      path
    ensure
      reader&.close
    end

    def flatten_entry_path(entry)
      path = nil

      loop do
        tree = rugged.lookup(entry[:oid])
        break if tree.count != 1

        entry = tree[0]
        break if entry[:type] != :tree
        path = File.join(path || "", entry[:name].b)
      end

      path
    end

    def entry_to_hash(entry, path, root_tree, options = {})
      opts = { :resolve_symlink => true,
               :full_blob       => false,
               :flatten_paths   => false,
               :skip_size       => false,
      }.merge(options)

      name = entry[:name].b

      full_path = File.join(path, name)
      full_path.gsub!(%r{\A(\.?/)*}, "")

      res = {
        "type" => entry[:type].to_s,
        "oid"  => entry[:oid],
        "mode" => entry[:filemode],
        "name" => name,
        "path" => full_path,
        "size" => nil
      }

      if entry[:type] == :blob
        if symlink?(entry[:filemode]) && opts[:resolve_symlink]
          sym_path, target = resolve_symlink(entry, path, root_tree)
          if target
            res["symlink_target"] = target[:oid]
            res["symlink_target_object"] = entry_to_hash(target, File.dirname(sym_path), root_tree, :resolve_symlink => false, :full_blob => false, :skip_size => opts[:skip_size])
          end
        end

        if !opts[:skip_size] || opts[:full_blob]
          header = rugged.read_header(entry[:oid])
          if opts[:full_blob]
            res.merge!(get_blob_object(entry[:oid], header, opts[:truncate], opts[:limit]))
          else
            res.merge!("size" => header[:len])
          end
        end
      end

      if opts[:flatten_paths] && entry[:type] == :tree
        if flat = flatten_entry_path(entry)
          res["simplified_path"] = File.join(full_path, flat)
        end
      end

      res
    end

  end
end

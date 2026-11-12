class BlobOperationsResponseHelper

  def tree_response(entries: [])
    BlobOperations::Responses::GetTree.new(client_response, tree_entries: entries)
  end

  def blob_response(content: "", oid: "unknown_sha", size_bytes: 0)
    BlobOperations::Responses::GetBlob.new(client_response, content: content, oid: oid, size_bytes: size_bytes)
  end

  TreeEntry = Struct.new(:path, :mode, :oid)
  def tree_response_entries(entries)
    entries.map do |entry|
      TreeEntry.new(entry[:path], entry[:mode], entry[:object_id])
    end
  end

  private

  def client_response
    Twirp::ClientResp.new(data: {})
  end
end

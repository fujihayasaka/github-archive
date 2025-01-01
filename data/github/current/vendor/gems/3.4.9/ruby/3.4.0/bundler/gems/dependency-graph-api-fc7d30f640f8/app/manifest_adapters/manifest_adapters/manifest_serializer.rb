class ManifestAdapters::ManifestSerializer < ActiveJob::Serializers::ObjectSerializer
  OBJECT_SERIALIZER_KEY = "_aj_serialized"
  def klass
    ManifestAdapters::Manifest
  end

  def serialize(manifest)
    hsh = manifest.to_h
    hsh[:dependencies] = hsh[:dependencies]&.map(&:to_h)
    super(hsh)
  end

  def deserialize(hash)
    # Filter our only symbol keys because the active job serializer
    # adds "_aj_serialized"=>"ManifestAdapters::ManifestSerializer"
    # to the hash The intention here would be to have a whitelist of
    # keys we use to serialize Manifest objects, but we may forget
    # to add new keys as we add them to the constructor. This way is
    # more permissive.
    hash.delete(OBJECT_SERIALIZER_KEY)
    hash.transform_keys!(&:to_sym)

    hash[:dependencies] = hash[:dependencies].map { |d| ManifestAdapters::Manifest::Dependency.new(**d.transform_keys(&:to_sym)) }
    ManifestAdapters::Manifest.new(**hash)

  end
end

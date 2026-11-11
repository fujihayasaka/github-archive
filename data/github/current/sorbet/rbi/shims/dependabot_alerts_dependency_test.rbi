# typed: true

# This file is a shim for DependabotAlertsSerializerTest which inherits from Api::SerializerTestCase. If the method names are ever changed in Api::Serializer, they will need to change here as well.

class DependabotAlertsSerializerTest
  sig { params(record: T.nilable(RepositoryVulnerabilityAlert), options: T.untyped).returns(T.nilable(Hash)) }
  def dependabot_alert(record, **options); end
end

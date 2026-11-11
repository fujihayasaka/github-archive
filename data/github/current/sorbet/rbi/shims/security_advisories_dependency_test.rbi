# typed: true

# This file is a shim for SecurityAdvisoriesDependencyTest which inherits from Api::SerializerTestCase. If the method names are ever changed in Api::Serializer, they will need to change here as well.

class SecurityAdvisorySerializerTest
  sig { params(advisory: T.nilable(SecurityAdvisory), options: T.untyped).returns(Hash) }
  def security_advisory(advisory, **options); end

  sig { params(vulnerability: T.nilable(SecurityVulnerability), options: T.untyped).returns(Hash) }
  def security_vulnerability(vulnerability, **options); end
end

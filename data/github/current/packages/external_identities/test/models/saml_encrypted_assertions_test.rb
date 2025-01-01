# typed: true
# frozen_string_literal: true
require "test_helper"

class SamlEncryptedAssertionsTest < GitHub::TestCase
  test "#human_name capitalizes each word" do
    key = "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEAwxCt6WmTsLrXnSSlZoRDnL87CIaMdURqgYDoUEJE6YUyqqaH\ndmKIABJYRTmKXlMIVy0929M73MFeNoo/7KvA96USUWgpdIFUjj2fkBDwlG/1iihf\n0DZH69QzLkSHp8NT9LgIqdcXQPZ+OcCVSunbxOs/UUREP2e/2PGnzmpffUOF0sYn\nTCVZiHDZwHWXwFj4K18Zhqd5NPZXI5Nwg1pyxnLVKkqL8BEIw1cYbTZ9HUl+xIUy\nMZLkMZJkN/Z9nOmw+T1zQKuF0NhxGkV6bvipfLbtXtaGYNbpFRpNx4BKWPz6beiX\naQXaDCIepFzej4zndyFbcDBFUX3GrKC6VZlzZwIDAQABAoIBAEDY26f8BDA9fQ5t\nr1rMX5nNbPehmzIk429YBmMgFL65HCXlJKVzjhjQAG5K+bfvzJcGoEjjCUSTOBnT\njfrFAmqRguxzP0zO7eg3jkMbjo8aRTt/vpJ+aRx6N+WKvLpF0jRJtf+YVM+w4jea\n0UbNRdVKC4udsT6O5BVgCNQzQrlmU1kWXzWlgQ5sgpjiPt5M/B0d8/E26WDKwwg2\n7hNHlDwkCRMPQof/ejYkkbaPukKiJExMLS79ANHhgBl3DJCAwtzGys+1/uNW1rQd\nJawFApm6roHC5w1yjqA9j27ihM67/RIogg/ZDPWwbhq9mK0AmOXvPNibs4apNxbD\nN9rkUBkCgYEA7DQ7EZ9ld41jGMwi5KZODDqVteUTmgQpZ8iJv7v3OMtr7zwUKihX\nabnT2o4RwqyJAeiSLx5n6YELzZUqVF6dIqJyqxfE4Uxftj7dc2ZD/HneYJA3f1Aw\nPvcuVOJPCO4kJ+zmLvjMjtzwkeiFpkVBmCD7VbUrJatGsaSF+9tvoQsCgYEA02nP\n4M+OiSOJuqPTJKYGDV5VEvDqi6mXFhKTRPUNetIxLC7zomEccveGmpokPKOsFx8V\nezHJWYa0CcOaI/YILX/6+VcCve3Wk+Hn6xochyS9390RrP8HykqF5xmxSdzcX4P2\nsMSZop6+osxpcf/yqwo9uZdvJ7qm1CvVPx3FKJUCgYEAoyqRg2Lw3N02j3K0x+56\nC8iMktJj8Ajf8Wl+foyCAyHCtchyxYyIlehgiKGLc0dsfX0DPrlqXsteM+3PB+kz\n8zD0tWv9/QSdOW/D2mvSmx40l9AIBlKGgXiO8OREZI7dOxdTCy+jXy0QojpV2L4O\nyeA+vr4fyC3A8AYO6CR1wHECgYAXXJf2FbmAegbcMwJACICetY/dGfYxHLpvW/oe\nIp4stlFsunt9tBF6utOK/gGHGecIXwz2ohfH5tS6R30fAC8DKCNJrk3FQyT1Dn+c\nQTRp0quQs1MitMPdnMKTOQmYSemoPGLkQbVgfP4/6yqzyD6+m9EaUxubXkrVI0rb\nQKTqyQKBgQC4Xm0FdGM+88Q01z1HeEqPtI/VY3P9fop3p7JVOl/OB8mCtQKEw0ro\nGljuqm0zcfhS5RhnY334yVa+Fc4Tya63jrNl38t5Bfe3MUK7TESmtcYVTQJ+/BT4\nnEKiqEJHgmGk0P0Xw64coqb1kdz3PUvRlHYvfRadUgzxu6rNSe9HlQ==\n-----END RSA PRIVATE KEY-----\n"
    cert_pem = SamlEncryptedAssertions.create_cert(OpenSSL::PKey::RSA.new(key), "Some Entity", "https://github.com/entity", nil)
    cert = OpenSSL::X509::Certificate.new(cert_pem)

    assert_equal "/C=US/ST=California/L=San Francisco/O=GitHub, Inc./OU=Some Entity/CN=https://github.com/entity", cert.subject.to_s
    assert_equal "/CN=github.com", cert.issuer.to_s
  end
end

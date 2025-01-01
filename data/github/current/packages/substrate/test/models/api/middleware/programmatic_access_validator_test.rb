# typed: true
# frozen_string_literal: true

require "test_helper"

class ApiMiddlewareProgrammaticAccessValidatorTest < GitHub::TestCase

  class PAVStubApi < Api::App
    get "/dummies/:id" do
      200
    end
  end

  class TestApp < Api::App
    get "/dummies/:id" do
      200
    end
  end

  test "allows requests for properly configured endpoints" do
    app = PAVStubApi.new!
    app.stubs(:call)

    env = {
      "REQUEST_METHOD"   => "GET",
      "PATH_INFO"        => "/dummies/123",
      "github.api.route" => "GET /dummies/:id",
    }

    fully_enabled_endpoints_config = {
      "GET /dummies/:id" => {
        "server_to_server" => {
          "enabled" => true
        },
        "user_to_server" => {
          "enabled" => true,
        }
      }
    }

    middleware = Api::Middleware::ProgrammaticAccessValidator.new(
      app, fully_enabled_endpoints_config,
    )

    assert_nothing_raised do
      middleware.call(env)
    end
  end

  test "allows requests without a github route" do
    app = PAVStubApi.new!
    app.stubs(:call)

    # This error is handled outside this middleware
    env = {
      "REQUEST_METHOD"   => "GET",
      "PATH_INFO"        => "/dummies/123",
    }

    fully_enabled_endpoints_config = {
      "GET /dummies/:id" => {
        "server_to_server" => {
          "enabled" => true
        },
        "user_to_server" => {
          "enabled" => true,
        }
      }
    }

    middleware = Api::Middleware::ProgrammaticAccessValidator.new(
      app, fully_enabled_endpoints_config,
    )

    assert_nothing_raised do
      middleware.call(env)
    end
  end

  test "allows requests if the endpoints config input is empty" do
    app = PAVStubApi.new!
    app.stubs(:call)

    env = {
      "REQUEST_METHOD"   => "GET",
      "PATH_INFO"        => "/dummies/123",
      "github.api.route" => "GET /dummies/:id",
    }

    middleware = Api::Middleware::ProgrammaticAccessValidator.new(
      app, {},
    )

    assert_nothing_raised do
      middleware.call(env)
    end
  end

  test "recognizes requests for routes containing escaped forward slashes" do
    app = PAVStubApi.new!
    app.stubs(:call)

    env = {
      "REQUEST_METHOD"   => "GET",
      "PATH_INFO"        => "/repositories/123/readme",
      "github.api.route" => "GET \\/repositories\\/(\\d+)\\/readme(?:\\/(.*))?",
    }

    endpoint_with_escaped_forward_slashes = {
      "GET /repositories/(\\d+)/readme(?:/(.*))?" => {
        "server_to_server" => {
          "enabled" => true,
        },
        "user_to_server" => {
          "enabled" => true,
        }
      }
    }

    middleware = Api::Middleware::ProgrammaticAccessValidator.new(
      app, endpoint_with_escaped_forward_slashes,
    )

    assert_nothing_raised do
      middleware.call(env)
    end
  end

  test "Allows HEAD requests with missing config if there's a GET entry" do
    app = PAVStubApi.new!
    app.stubs(:call)

    env = {
      "REQUEST_METHOD"   => "HEAD",
      "PATH_INFO"        => "/repositories/123/contents",
      "github.api.route" => "HEAD /repositories/:repository_id/contents/?*",
    }

    get_endpoint_config = {
      "GET /repositories/:repository_id/contents/?*" => {
        "server_to_server" => {
          "enabled" => true,
        },
        "user_to_server" => {
          "enabled" => true,
        }
      }
    }

    middleware = Api::Middleware::ProgrammaticAccessValidator.new(
      app, get_endpoint_config,
    )

    assert_nothing_raised do
      middleware.call(env)
    end
  end

  test "does not validate requests for endpoints defined under test classes" do
    app = TestApp.new!
    app.stubs(:call)

    env = {
      "REQUEST_METHOD"   => "GET",
      "PATH_INFO"        => "/dummies/123",
      "github.api.route" => "GET /dummies/:id",
    }

    configuration_for_endpoint_defined_in_a_test_class = {
      "GET /dummies/:id" => {
        "server_to_server" => {
          "enabled" => false
        },
        "user_to_server" => {
          "enabled" => false,
        }
      }
    }

    middleware = Api::Middleware::ProgrammaticAccessValidator.new(
      app, configuration_for_endpoint_defined_in_a_test_class,
    )

    # Nothing is raised because _this_ endpoint is being defined
    # under TestApp
    assert_nothing_raised do
      middleware.call(env)
    end
  end

  test "does not validate requests matching the ignored paths" do
    app = PAVStubApi.new!
    app.stubs(:call)

    env = {
      "REQUEST_METHOD"   => "POST",
      "PATH_INFO"        => "/graphql",
      "github.api.route" => "POST /graphql",
    }

    endpoints_config = {
      "GET /dummies/:id" => {
        "server_to_server" => {
          "enabled" => false
        },
        "user_to_server" => {
          "enabled" => false,
        }
      }
    }

    middleware = Api::Middleware::ProgrammaticAccessValidator.new(
      app, endpoints_config,
    )

    # Nothing is raised because we ignore /graphql
    assert_nothing_raised do
      middleware.call(env)
    end
  end

  test "raises an exception if the endpoint doesn't have a configuration entry" do
    app = PAVStubApi.new!
    app.stubs(:call)

    env = {
      "REQUEST_METHOD"   => "GET",
      "PATH_INFO"        => "/dummies/123",
      "github.api.route" => "GET /dummies/:id",
    }

    missing_configuration_for_dummies = {
      "GET /def-not-dummies/:id" => {
        "server_to_server" => {
          "enabled" => true
        },
        "user_to_server" => {
          "enabled" => true,
        }
      }
    }

    middleware = Api::Middleware::ProgrammaticAccessValidator.new(
      app, missing_configuration_for_dummies,
    )

    exception = assert_raises Api::ProgrammaticAccessValidator::ConfigurationError do
      middleware.call(env)
    end

    assert_equal :missing_endpoint_configuration, exception.reason
    assert_match "endpoint must have a configuration entry under", exception.message
  end

  context "server_to_server" do
    test "raises an exception if server_to_server is disabled without a reason" do
      app = PAVStubApi.new!
      app.stubs(:call)

      env = {
        "REQUEST_METHOD"   => "GET",
        "PATH_INFO"        => "/dummies/123",
        "github.api.route" => "GET /dummies/:id",
      }

      exempted_server_to_server_without_linked_issue_endpoint_config = {
        "GET /dummies/:id" => {
          "server_to_server" => {
            "enabled" => false,
          },
          "user_to_server" => {
            "enabled" => true,
          }
        }
      }

      middleware = Api::Middleware::ProgrammaticAccessValidator.new(
        app, exempted_server_to_server_without_linked_issue_endpoint_config,
      )

      exception = assert_raises Api::ProgrammaticAccessValidator::ConfigurationError do
        middleware.call(env)
      end

      assert_equal :missing_reason_for_disabled_token, exception.reason
      assert_equal "server_to_server", exception.token_type
      assert_match "endpoint is currently disabled for server_to_server", exception.message
    end

    test "raises an exception if server_to_server is disabled without a valid reason" do
      app = PAVStubApi.new!
      app.stubs(:call)

      env = {
        "REQUEST_METHOD"   => "GET",
        "PATH_INFO"        => "/dummies/123",
        "github.api.route" => "GET /dummies/:id",
      }

      exempted_server_to_server_without_a_valid_github_issue_endpoint_config = {
        "GET /dummies/:id" => {
          "server_to_server" => {
            "enabled" => false,
            # issues must be created under github/api-permissions
            "reason" => "https://github.com/github/ecosystem-apps/issues/123",
          },
          "user_to_server" => {
            "enabled" => true,
          }
        }
      }

      middleware = Api::Middleware::ProgrammaticAccessValidator.new(
        app, exempted_server_to_server_without_a_valid_github_issue_endpoint_config,
      )

      exception = assert_raises Api::ProgrammaticAccessValidator::ConfigurationError do
        middleware.call(env)
      end

      assert_equal :invalid_reason_for_disabled_token, exception.reason
      assert_equal "server_to_server", exception.token_type
      assert_match "endpoint is currently disabled for server_to_server", exception.message
    end

    test "doesn't raise an exception if server_to_server is disabled with a valid reason" do
      app = PAVStubApi.new!
      app.stubs(:call)

      env = {
        "REQUEST_METHOD"   => "GET",
        "PATH_INFO"        => "/dummies/123",
        "github.api.route" => "GET /dummies/:id",
      }

      exempted_server_to_server_with_a_valid_github_issue_endpoint_config = {
        "GET /dummies/:id" => {
          "server_to_server" => {
            "enabled" => false,
            "reason" => "https://github.com/github/api-permissions/issues/123"
          },
          "user_to_server" => {
            "enabled" => true,
          }
        }
      }

      middleware = Api::Middleware::ProgrammaticAccessValidator.new(
        app, exempted_server_to_server_with_a_valid_github_issue_endpoint_config,
      )

      assert_nothing_raised do
        middleware.call(env)
      end
    end

    test "raises an exception if server_to_server is disabled with an invalid reason" do
      app = PAVStubApi.new!
      app.stubs(:call)

      env = {
        "REQUEST_METHOD"   => "GET",
        "PATH_INFO"        => "/dummies/123",
        "github.api.route" => "GET /dummies/:id",
      }

      disabled_internal_server_to_server_with_an_invalid_reason = {
        "GET /dummies/:id" => {
          "server_to_server" => {
            "enabled" => false,
            # reasons must be created under github/api-permissions
            "reason" => "https://github.com/github/ecosystem-apps/issues/123",
          },
          "user_to_server" => {
            "enabled" => true,
          }
        }
      }

      middleware = Api::Middleware::ProgrammaticAccessValidator.new(
        app, disabled_internal_server_to_server_with_an_invalid_reason,
      )
      exception = assert_raises Api::ProgrammaticAccessValidator::ConfigurationError do
        middleware.call(env)
      end

      assert_equal :invalid_reason_for_disabled_token, exception.reason
      assert_equal "server_to_server", exception.token_type
      assert_match "for server_to_server access", exception.message
      assert_match "endpoint is currently disabled", exception.message
    end
  end

  context "user_to_server" do
    test "raises an exception if user_to_server is disabled without a reason" do
      app = PAVStubApi.new!
      app.stubs(:call)

      env = {
        "REQUEST_METHOD"   => "GET",
        "PATH_INFO"        => "/dummies/123",
        "github.api.route" => "GET /dummies/:id",
      }

      exempted_user_to_server_without_linked_issue_endpoint_config = {
        "GET /dummies/:id" => {
          "user_to_server" => {
            "enabled" => false,
          },
          "server_to_server" => {
            "enabled" => true,
          }
        }
      }

      middleware = Api::Middleware::ProgrammaticAccessValidator.new(
        app, exempted_user_to_server_without_linked_issue_endpoint_config,
      )

      exception = assert_raises Api::ProgrammaticAccessValidator::ConfigurationError do
        middleware.call(env)
      end

      assert_equal :missing_reason_for_disabled_token, exception.reason
      assert_equal "user_to_server", exception.token_type
      assert_match "currently disabled for user_to_server access", exception.message
    end

    test "raises an exception if user_to_server is disabled with an invalid reason" do
      app = PAVStubApi.new!
      app.stubs(:call)

      env = {
        "REQUEST_METHOD"   => "GET",
        "PATH_INFO"        => "/dummies/123",
        "github.api.route" => "GET /dummies/:id",
      }

      exempted_user_to_server_without_a_valid_github_issue_endpoint_config = {
        "GET /dummies/:id" => {
          "user_to_server" => {
            "enabled" => false,
            # reasons must be created under github/api-permissions
            "reason" => "https://github.com/ecosystem-apps/issues/123",
          },
          "server_to_server" => {
            "enabled" => true,
          }
        }
      }

      middleware = Api::Middleware::ProgrammaticAccessValidator.new(
        app, exempted_user_to_server_without_a_valid_github_issue_endpoint_config,
      )

      exception = assert_raises Api::ProgrammaticAccessValidator::ConfigurationError do
        middleware.call(env)
      end

      assert_equal :invalid_reason_for_disabled_token, exception.reason
      assert_equal "user_to_server", exception.token_type
      assert_match "currently disabled for user_to_server access", exception.message
    end

    test "doesn't raise an exception if user_to_server is disabled with a valid reason" do
      app = PAVStubApi.new!
      app.stubs(:call)

      env = {
        "REQUEST_METHOD"   => "GET",
        "PATH_INFO"        => "/dummies/123",
        "github.api.route" => "GET /dummies/:id",
      }

      exempted_user_to_server_with_a_valid_github_issue_endpoint_config = {
        "GET /dummies/:id" => {
          "user_to_server" => {
            "enabled" => false,
            "reason" => "https://github.com/github/api-permissions/issues/123",
          },
          "server_to_server" => {
            "enabled" => true,
          }
        }
      }

      middleware = Api::Middleware::ProgrammaticAccessValidator.new(
        app, exempted_user_to_server_with_a_valid_github_issue_endpoint_config,
      )

      assert_nothing_raised do
        middleware.call(env)
      end
    end

    test "it raises an exception for enterprise APIs without a valid permissions review issue" do
      app = PAVStubApi.new!
      app.stubs(:call)

      env = {
        "REQUEST_METHOD"   => "GET",
        "PATH_INFO"        => "/:enterprise_id/",
        "github.api.route" => "GET /:enterprise_id/dummies",
      }

      config = {
        "GET /:enterprise_id/dummies" => {
          "user_to_server" => { "enabled" => true },
          "server_to_server" => { "enabled" => true },
          "permission_sets" => [{ "enterprise_administration" => :read }],
        }
      }

      middleware = Api::Middleware::ProgrammaticAccessValidator.new(app, config,)

      exception = assert_raises Api::ProgrammaticAccessValidator::ConfigurationError do
        middleware.call(env)
      end

      assert_equal :invalid_permissions_review, exception.reason
      assert_match "must have a valid permission review issue", exception.message
      assert_match "https://github.com/github/permissions/issues/new?template=01_permissions_review.md", exception.message
    end

    test "it does not raise an exception for enterprise APIs with a valid permissions review issue" do
      app = PAVStubApi.new!
      app.stubs(:call)

      env = {
        "REQUEST_METHOD"   => "GET",
        "PATH_INFO"        => "/:enterprise_id/",
        "github.api.route" => "GET /:enterprise_id/dummies",
      }

      config = {
        "GET /:enterprise_id/dummies" => {
          "user_to_server" => { "enabled" => true },
          "server_to_server" => { "enabled" => true },
          "permission_sets" => [{ "enterprise_administration" => :read }],
          "permissions_review" => "https://github.com/github/api-permissions/issues/123",
        }
      }

      middleware = Api::Middleware::ProgrammaticAccessValidator.new(app, config,)
      assert_nothing_raised do
        middleware.call(env)
      end
    end
  end
end

# typed: true
# frozen_string_literal: true

module Faraday
  class Adapter
    class PersistentExcon < Faraday::Adapter
      dependency "excon"

      def call(env)
        super

        retries = 0
        opts = timeouts(env[:request])
        opts.merge! \
          path: env[:url].path,
          query: env[:url].query,
          method: env[:method].to_s.upcase,
          headers: env[:request_headers],
          body: read_body(env)

        begin
          resp = conn(env).request(opts)
          save_response(env, resp.status.to_i, resp.body, resp.headers)

          @app.call env
        rescue ::Excon::Errors::SocketError => err
          if err.message =~ /\btimeout\b/
            raise Faraday::TimeoutError, err
          elsif err.message =~ /\bcertificate\b/
            raise Faraday::SSLError, err
          else
            retry if (retries += 1) <= 2
            raise Faraday::ConnectionFailed, err
          end
        rescue ::Excon::Errors::Timeout => err
          raise Faraday::TimeoutError, err
        end
      end

      # TODO: support streaming requests
      def read_body(env)
        env[:body].respond_to?(:read) ? env[:body].read : env[:body]
      end

      def conn(env)
        return @conn if defined?(@conn) && !@conn.nil?

        url = env[:url].dup
        url.path = ""
        url.query = nil

        opts = { persistent: true }.merge(@connection_options)

        if url.scheme == "https" && ssl = env[:ssl]
          opts[:ssl_verify_peer] = !!ssl.fetch(:verify, true)
          opts[:ssl_ca_path] = ssl[:ca_path] if ssl[:ca_path]
          opts[:ssl_ca_file] = ssl[:ca_file] if ssl[:ca_file]
          opts[:client_cert] = ssl[:client_cert] if ssl[:client_cert]
          opts[:client_key]  = ssl[:client_key]  if ssl[:client_key]
          opts[:certificate] = ssl[:certificate] if ssl[:certificate]
          opts[:private_key] = ssl[:private_key] if ssl[:private_key]

          # https://github.com/geemus/excon/issues/106
          # https://github.com/jruby/jruby-ossl/issues/19
          opts[:nonblock] = false
        end

        if (req = env[:request])
          if req[:timeout]
            opts[:read_timeout]    = req[:timeout]
            opts[:connect_timeout] = req[:timeout]
            opts[:write_timeout]   = req[:timeout]
          end

          if req[:open_timeout]
            opts[:connect_timeout] = req[:open_timeout]
            opts[:write_timeout]   = req[:open_timeout]
          end

          if req[:proxy]
            opts[:proxy] = {
              host: req[:proxy][:uri].host,
              port: req[:proxy][:uri].port,
              scheme: req[:proxy][:uri].scheme,
              user: req[:proxy][:user],
              password: req[:proxy][:password],
            }
          end
        end

        @conn = ::Excon.new(url.to_s, opts)
      end

      def timeouts(req)
        opts = {}
        return opts unless req

        if req[:timeout]
          opts[:read_timeout]    = req[:timeout]
          opts[:connect_timeout] = req[:timeout]
          opts[:write_timeout]   = req[:timeout]
        end

        if req[:open_timeout]
          opts[:connect_timeout] = req[:open_timeout]
          opts[:write_timeout]   = req[:open_timeout]
        end

        opts
      end
    end

    register_middleware \
      persistent_excon: :PersistentExcon

  end
end

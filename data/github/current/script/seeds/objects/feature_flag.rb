# typed: strict
# frozen_string_literal: true

# Do not require anything here. If you need something else, require it in the method that needs it.
# This makes sure the boot time of our seeds stays low.

module Seeds
  module Objects
    class FeatureFlag
      sig { params(action: T.any(Symbol, String), feature_flag: T.any(String, Symbol), actor_name: T.nilable(String), diagnostic_io:  T.any(StringIO, IO)).returns(FlipperFeature) }
      def self.toggle(action:, feature_flag:, actor_name: nil, diagnostic_io: $stdout)
        feature = ensure_feature_flag_exists(feature_flag, diagnostic_io)
        if actor_name.nil?

          GitHub.flipper[feature_flag].method(action).call
          diagnostic_io.puts "#{feature_flag} globally #{action}d"
          return feature
        end

        actor = if actor_name.start_with?("business:")
          ::Business.find_by(slug: actor_name.gsub("business:", ""))
        else
          GitHub::Resources.find_by_url(actor_name, suppress_warning: true)
        end

        if actor.nil?
          raise Objects::ActionFailed, "Couldn't find the actor #{actor_name}"
        end

        begin
          feature.method(action).call(actor)
          diagnostic_io.puts "#{feature_flag} #{action}d for #{actor_name}"
          feature
        rescue ::Flipper::GateNotFound
          raise Objects::ActionFailed, "Something went wrong when trying to #{action} #{feature_flag} for #{actor_name}"
        end
      end

      sig { params(feature_flag: T.any(String, Symbol), actor: T.nilable(T.all(Vexi::Actor, GitHub::IFlipperActor)), diagnostic_io:  T.any(StringIO, IO)).void }
      def self.enable(feature_flag:, actor: nil, diagnostic_io: $stdout)
        ensure_feature_flag_exists(feature_flag, diagnostic_io)
        if actor.nil?
          GitHub.flipper[feature_flag].enable
        else
          GitHub.flipper.enable(feature_flag, actor)
        end
      end

      sig { params(feature_flag: T.any(String, Symbol), actor: T.nilable(T.all(Vexi::Actor, GitHub::IFlipperActor)), diagnostic_io:  T.any(StringIO, IO)).void }
      def self.disable(feature_flag:, actor: nil, diagnostic_io: $stdout)
        ensure_feature_flag_exists(feature_flag, diagnostic_io)

        if actor.nil?
          GitHub.flipper[feature_flag].disable
        else
          GitHub.flipper.disable(feature_flag, actor)
        end
      end

      sig { params(feature_flag: T.any(String, Symbol), diagnostic_io: T.any(StringIO, IO)).returns(FlipperFeature) }
      private_class_method def self.ensure_feature_flag_exists(feature_flag, diagnostic_io)
        feature = ::FlipperFeature.find_by(name: feature_flag)

        if feature.nil?
          diagnostic_io.puts "Creating #{feature_flag}"
          GitHub.flipper.disable(feature_flag)
          feature = T.must(FlipperFeature.find_by(name: feature_flag))
        end

        feature
      end
    end
  end
end

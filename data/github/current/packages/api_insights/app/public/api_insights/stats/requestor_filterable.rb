# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  module RequestorFilterable
    extend T::Helpers

    abstract!
    requires_ancestor { StatsBase }

    sig { params(user_id: Integer).returns(T.self_type) }
    def with_user(user_id)
      query.filters << Queries::Filter.new(Queries::FilterField::SubjectId, user_id)
      query.filters << Queries::Filter.new(Queries::FilterField::SubjectType, SubjectType::User.serialize)

      query.summary_key_fields << Queries::SummaryKeyField::SubjectId
      query.summary_key_fields << Queries::SummaryKeyField::SubjectName
      self
    end

    sig { params(access_id: Integer).returns(T.self_type) }
    def with_oauth_app(access_id)
      query.filters << Queries::Filter.new(Queries::FilterField::ActorId, access_id)
      query.filters << Queries::Filter.new(Queries::FilterField::ActorType, ActorType::OauthApp.serialize)

      query.summary_key_fields << Queries::SummaryKeyField::ActorId
      query.summary_key_fields << Queries::SummaryKeyField::ActorName
      query.summary_key_fields << Queries::SummaryKeyField::SubjectId
      query.summary_key_fields << Queries::SummaryKeyField::SubjectName
      self
    end

    sig { params(access_id: Integer).returns(T.self_type) }
    def with_classic_pat(access_id)
      query.filters << Queries::Filter.new(Queries::FilterField::ActorId, access_id)
      query.filters << Queries::Filter.new(Queries::FilterField::ActorType, ActorType::ClassicPat.serialize)

      query.summary_key_fields << Queries::SummaryKeyField::ActorId
      query.summary_key_fields << Queries::SummaryKeyField::ActorName
      query.summary_key_fields << Queries::SummaryKeyField::SubjectId
      query.summary_key_fields << Queries::SummaryKeyField::SubjectName
      self
    end

    sig { params(access_id: Integer).returns(T.self_type) }
    def with_fine_grained_pat(access_id)
      query.filters << Queries::Filter.new(Queries::FilterField::ActorId, access_id)
      query.filters << Queries::Filter.new(Queries::FilterField::ActorType, ActorType::FineGrainedPat.serialize)

      query.summary_key_fields << Queries::SummaryKeyField::ActorId
      query.summary_key_fields << Queries::SummaryKeyField::ActorName
      query.summary_key_fields << Queries::SummaryKeyField::SubjectId
      query.summary_key_fields << Queries::SummaryKeyField::SubjectName
      self
    end

    sig { params(access_id: Integer).returns(T.self_type) }
    def with_github_app_user_to_server(access_id)
      query.filters << Queries::Filter.new(Queries::FilterField::ActorId, access_id)
      query.filters << Queries::Filter.new(Queries::FilterField::ActorType, ActorType::GithubAppUserToServer.serialize)

      query.summary_key_fields << Queries::SummaryKeyField::ActorId
      query.summary_key_fields << Queries::SummaryKeyField::ActorName
      query.summary_key_fields << Queries::SummaryKeyField::SubjectId
      query.summary_key_fields << Queries::SummaryKeyField::SubjectName
      self
    end

    sig { params(installation_id: Integer).returns(T.self_type) }
    def with_installation(installation_id)
      query.filters << Queries::Filter.new(Queries::FilterField::ActorId, installation_id)
      query.filters << Queries::Filter.new(Queries::FilterField::ActorType, ActorType::Installation.serialize)

      query.summary_key_fields << Queries::SummaryKeyField::ActorId
      query.summary_key_fields << Queries::SummaryKeyField::ActorName
      self
    end
  end
end

# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class Ability < Platform::Loader
      include Scientist

      CACHE_PREFIX = "ability_loader"

      def self.load(actor, subject)
        actor = actor.ability_delegate
        subject = subject.ability_delegate

        return ::Promise.resolve(nil) unless actor && subject
        return ::Promise.resolve(nil) unless actor.ability_id && subject.ability_id

        if PermissionCache.enabled?
          cache_key = [CACHE_PREFIX, actor.ability_type, actor.ability_id, subject.ability_type, subject.ability_id]
          cached = PermissionCache.key?(cache_key)
          GitHub.dogstats.count("platform_loader_ability.count", 1, tags: ["cached:#{cached}"])
          # temporary fix to record cache misses
          GitHub.dogstats.increment("ability.cache", tags: ["result:miss", "namespace:ability_loader"]) unless cached
          return ::Promise.resolve(PermissionCache.get(cache_key)) if cached
        end

        # A simpler `actor == subject` triggers `method_missing` when using `CollectionProxy` instances as actors or subjects,
        # causing the entire association to be queried and loaded
        if actor.ability_type == subject.ability_type && actor.ability_id == subject.ability_id
          # everyone has autonomy over themselves
          return ::Promise.resolve(::Ability.actions[:admin])
        end
        self.for(actor.ability_type, subject.ability_type).load([actor, subject])
      end

      def initialize(actor_type, subject_type)
        @actor_type = actor_type
        @subject_type = subject_type
      end

      # Cleaning function for `ability_loader_query` experiment
      # Format of the results is:
      # [[actor, subject, action], [actor, subject, action], [actor, subject, action] ...]
      # where actor is an object such as User, subject is an object such as Repository,
      # Project, etc, and action is an Ability value (0 - read, 1 - write, or 2 - admin).
      def clean_result(result)
        clean_res = Hash.new
        result.map do |res|
          identification = "#{res[0].id}_#{res[0].class.name}:#{res[1].ability_id}_#{res[1].class.name}"
          if clean_res.key?(identification)
            clean_res[identification] = clean_res[identification] < res[2] ? res[2] : clean_res[identification]
          else
            clean_res[identification] = res[2]
          end
        end
        clean_res.sort.to_h
      end

      def fetch(actors_and_subjects)
        owning_org_ids = owning_organization_ids(actors_and_subjects)
        results = fetch_results_for(actors_and_subjects, owning_org_ids)
        fetched_results = results.each_with_object({}) do |(actor_id, subject_id, action), result|
          key = [actor_id, subject_id]
          current_action = result[key]

          if current_action.nil? || current_action < action
            result[key] = action
          end
        end
        actors_and_subjects.each do |actor, subject|
          actor_id = actor.ability_id
          subject_id = subject.ability_id
          PermissionCache.set([CACHE_PREFIX, @actor_type, actor_id, @subject_type, subject_id], fetched_results[[actor, subject]])
        end
        fetched_results
      end

      private

      def all_same_actor?(actors_and_subjects)
        first_actor = actors_and_subjects.first.first
        actors_and_subjects.all? { |(actor, _subject)| actor == first_actor }
      end

      def fetch_results_for(actors_and_subjects, owning_org_ids)
        GitHub.dogstats.distribution_time("platform.loaders.ability.fetch_results_for.dist") do
          map_results(
            results_with_ids: union_results_with_orgs(actors_and_subjects, owning_org_ids),
            actors_and_subjects: actors_and_subjects,
            owning_org_ids: owning_org_ids)
        end
      end

      # Determine the owning organization of the subjects
      # Returns a hash indexed by subject_id
      def owning_organization_ids(actors_and_subjects)
        return {} if actors_and_subjects.empty?
        subjects = actors_and_subjects.map(&:second).uniq

        case @subject_type
        when "Team"
          subjects.each_with_object({}) do |team, owning_org_ids|
            owning_org_ids[team.id] = team.organization_id
          end
        when "Project"
          subjects.each_with_object({}) do |project, owning_org_ids|
            if project.owner_type == "Organization"
              owning_org_ids[project.id] = project.owner_id
            end
          end
        when "Repository"
          # Batch-load parent and owner for owning_organization_id method
          GitHub::PrefillAssociations.prefill_associations(subjects, [:parent, :owner])
          subjects.each_with_object({}) do |repo, owning_org_ids|
            owning_org_ids[repo.id] = repo.owning_organization_id if repo.owning_organization_id.present?
          end
        else
          {}
        end
      end

      def union_results_with_orgs(actors_and_subjects, owning_org_ids)
        router = ::Permissions::QueryRouter.for(subject_types: [@subject_type])
        options = { actor_type: @actor_type,
                   subject_type: @subject_type }

        if all_same_actor?(actors_and_subjects)
          options[:actor_id] = actors_and_subjects.first.first.ability_id
        end

        model = router.model
        options[:admin] = ::Ability.actions[:admin]
        options[:direct] = ::Ability.priorities[:direct]
        options[:abilities_or_permissions] = Arel.sql(model.table_name)
        actor_sql = Arel.sql(<<~SQL, **options)
          SELECT actor.actor_id, actor.subject_id, actor.subject_type, actor.action
          FROM :abilities_or_permissions actor
          WHERE actor.actor_type = :actor_type AND actor.subject_type = :subject_type
          AND actor.priority <= :direct AND ((
        SQL

        actors_and_subjects.each_with_index do |(actor, subject), index|
          actor_sql += Arel.sql(") OR (") if index > 0
          actor_sql += Arel.sql(<<~SQL, actor_id: actor.ability_id, subject_id: subject.ability_id)
            actor.actor_id = :actor_id AND actor.subject_id = :subject_id
          SQL
        end
        actor_sql += Arel.sql("))")

        ancestor_sql = Arel.sql(<<~SQL, **options)
          SELECT grandparent.actor_id, parent.subject_id, parent.subject_type, parent.action
          FROM   :abilities_or_permissions parent
          /* abilities-join-audited */
          JOIN   :abilities_or_permissions grandparent
          ON     grandparent.subject_type = parent.actor_type
          AND    grandparent.subject_id   = parent.actor_id
          AND    parent.priority          <= :direct
          AND    grandparent.priority     <= :direct
          WHERE  grandparent.actor_type = :actor_type AND parent.subject_type = :subject_type AND
        SQL
        ancestor_sql += Arel.sql("((")

        actors_and_subjects.each_with_index do |(actor, subject), index|
          ancestor_sql += Arel.sql(") OR (") if index > 0
          ancestor_sql += Arel.sql(<<~SQL, actor_id: actor.ability_id, subject_id: subject.ability_id)
            grandparent.actor_id = :actor_id AND parent.subject_id = :subject_id
          SQL
        end

        ancestor_sql += Arel.sql("))")

        union_sql = actor_sql + Arel.sql(" UNION ") + ancestor_sql

        if !owning_org_ids.empty?
          organization_owner_sql = Arel.sql(<<~SQL, **options)
            SELECT owning_org.actor_id, owning_org.subject_id, owning_org.subject_type, owning_org.action
            FROM :abilities_or_permissions owning_org
            WHERE (
          SQL

          org_index = 0
          actors_and_subjects.each do |actor, subject|
            org_id = owning_org_ids[subject.ability_id]
            next if org_id.nil?
            org_index += 1
            organization_owner_sql += Arel.sql(") OR (") if org_index > 1
            organization_owner_sql += Arel.sql(<<~SQL, **(options.merge(actor_id: actor.ability_id, owning_org_id: org_id)))
              owning_org.actor_id = :actor_id AND
              owning_org.subject_id = :owning_org_id AND
              owning_org.actor_type = :actor_type AND
              owning_org.subject_type = 'Organization' AND
              owning_org.action = :admin AND
              owning_org.priority = :direct
            SQL
          end
          organization_owner_sql += Arel.sql(")")
          union_sql += Arel.sql(" UNION ") + organization_owner_sql
        end
        model.connection.select_rows(union_sql)
      end

      # Transform [[actor_id, subject_id, subject_type, action]]
      # into      [[actor, subject, action]]
      # so the results line up with the arguments to load:
      #           load([actor, subject])
      def map_results(results_with_ids:, actors_and_subjects:, owning_org_ids:)
        actors_by_id = {}
        subjects_by_id = {}
        subjects_by_org_id = Hash.new { |h, k| h[k] = [] }
        expected_pairs = Set.new

        actors_and_subjects.each do |actor, subject|
          actors_by_id[actor.ability_id] = actor
          subjects_by_id[subject.ability_id] = subject
          expected_pairs.add("#{actor.ability_id}-#{subject.ability_id}")
        end

        if GitHub.flipper[:ability_loader_size_metric].enabled?
          GitHub.dogstats.distribution("platform.loaders.ability.expected_pairs.dist", expected_pairs.size)
        end

        owning_org_ids.each do |subject_id, org_id|
          subjects_by_org_id[org_id] << subjects_by_id[subject_id]
        end

        results = []
        results_with_ids.each do |actor_id, subject_id, subject_type, action|
          if subjects_by_org_id.has_key?(subject_id) && subject_type == "Organization"
            subjects_by_org_id[subject_id].each do |s|
              if expected_pairs.include? "#{actor_id}-#{s.ability_id}"
                results << [actors_by_id[actor_id], s, action]
              end
            end
          else
            results << [actors_by_id[actor_id], subjects_by_id[subject_id], action]
          end
        end
        results
      end
    end
  end
end

# typed: true
# frozen_string_literal: true

# Record archive and restore
#
# The models defined under the Archived::* namespace are used to perform record
# archiving and restoration to a set of mirror tables. The archived_* table
# schemas must be identical to their corresponding active table.
#
# == Archiving
#
# Archiving copies a live record and any associated (via has_one or has_many)
# archive record types to archive tables and then destroys the live record
# using AR's normal destroy machinery.
#
# == Restoring
#
# Restoring copies an archived record and any associated archive record types to
# their correspond live tables and then destroys the archived record using AR's
# normal destroy machinery.
#
# == Associations
#
# The archive and restore methods automatically cascade to associations defined
# on the archive model. For instance, given the following:
#
#     class Archived::Person < ApplicationRecord::Domain::<ConnectionClass>
#       include Archived::Base
#       has_many :arms, :class_name => 'Archived::Arms', :dependent => :delete_all
#       has_many :legs, :class_name => 'Archived::Legs', :dependent => :delete_all
#     end
#
#     class Archived::Leg < ApplicationRecord::Domain::<ConnectionClass>
#       include Archived::Base
#     end
#
#     class Archived::Arm < ApplicationRecord::Domain::<ConnectionClass>
#       include Archived::Base
#     end
#
# Now, if you archive a Person record, associated objects are archived at the
# same time. Same deal with restoring.
#
# If you need to archive an association's association then you should create a
# through association on the model you are wanting to archive.
# For instance, given the following:
#
#     class Archived::Person < ApplicationRecord::Domain::<ConnectionClass>
#       include Archived::Base
#       has_many :arms, :class_name => 'Archived::Arms', :dependent => :delete_all
#       has_many :hands, :through => :arms
#       has_many :legs, :class_name => 'Archived::Legs', :dependent => :delete_all
#     end
#
#     class Archived::Leg < ApplicationRecord::Domain::<ConnectionClass>
#       include Archived::Base
#     end
#
#     class Archived::Arm < ApplicationRecord::Domain::<ConnectionClass>
#       include Archived::Base
#       has_many :hands,  :class_name => "Archived::Hands", :dependent => :delete_all
#     end
#
#     class Archived::Hands < ApplicationRecord::Domain::<ConnectionClass>
#       include Archived::Base
#     end
#
# Here we added a through association, hands, on the model we want to archive,
# Person. Then we updated Archived::Arm to include the has_many association for
# Archived::Hands. Now, when we archive a Person record, arms, hands and legs
# are archived at the same time. Same deal with restoring.
#
# See the Archived::Base module for more information on these methods.
module Archived
end

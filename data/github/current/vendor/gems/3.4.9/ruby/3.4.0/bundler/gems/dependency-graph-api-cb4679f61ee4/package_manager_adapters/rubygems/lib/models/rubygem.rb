module Models
  class Rubygem < Base
    has_many :versions
    has_one :linkset
  end
end

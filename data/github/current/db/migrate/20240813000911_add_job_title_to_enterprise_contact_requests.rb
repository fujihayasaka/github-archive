class AddJobTitleToEnterpriseContactRequests < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Site)

  def change
    add_column :enterprise_contact_requests, :job_title, :string
  end
end

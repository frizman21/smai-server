class AddCustomerPhoneToJobProposals < ActiveRecord::Migration[8.0]
  def change
    add_column :job_proposals, :customer_phone, :string
  end
end

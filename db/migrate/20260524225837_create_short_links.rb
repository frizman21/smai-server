class CreateShortLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :short_links do |t|
      t.string :code, null: false
      t.text :target_url, null: false
      t.timestamps
    end
    add_index :short_links, :code, unique: true
  end
end

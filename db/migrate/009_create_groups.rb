class CreateGroups < ActiveRecord::Migration[4.2]
  def self.up
    create_table :groups do |t|

      t.timestamps
    end
  end

  def self.down
    drop_table :groups
  end
end

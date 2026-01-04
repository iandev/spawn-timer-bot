Sequel.migration do
  up do
    create_table(:earthquakes) do
      primary_key :id
      Decimal :timestamp
      DateTime :created_at
    end
  end

  down do
    drop_table(:earthquakes)
  end
end

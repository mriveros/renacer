class CreateImpuestos < ActiveRecord::Migration[5.0]
  def change
    create_table :impuestos do |t|
      t.string :descripcion
      t.float :porcentaje
      t.timestamps
    end
  end
end

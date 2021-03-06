require 'sequel'
require 'csv'
require 'yaml'
require './dic'
require './terms'

class DBSetup
  attr_accessor :db
  TABLE_NAMES = %w(company_names car_names car_types specs stocks)

  def initialize
    connect_opt = YAML.load_file('./config.yml')
    @db = Sequel.postgres('h28_j5_g3', connect_opt)
  end

  def run
    car_specs = assemble_hash
    reset_db
    setup_db(car_specs)
  end

  def assemble_hash
    car_specs = {}
    Dir.glob("./csv_files/*.csv").each do |path|
      data = csv_parse(path)
      key = File.basename(path, ".csv")
      car_specs[key] = data
    end
    car_specs
  end

  def setup_db(car_specs)
    TABLE_NAMES.each do |table_name|
      self.send("setup_#{table_name}", car_specs)
    end
    setup_terms(TERMS)
  end

  def reset_db
    @db.run('DROP SCHEMA public CASCADE;')
    @db.run('CREATE SCHEMA public;')
    system('psql -f ./create_tables.sql -d h28_j5_g3')
  end

  private
  def csv_parse(path)
    car_specs = []
    CSV.foreach("./" + path) do |line|
      if (line[0] && line[0] != "車両形式")
        a = [DICTIONARY, line].transpose
        car_specs << Hash[*a.flatten]
      end
    end

    car_specs
  end

  def setup_company_names(car_specs)
    @db.transaction do
      car_specs.each_key do |company_name|
        @db[:company_names].insert(name: company_name)
      end
    end
  end

  def setup_car_names(car_specs)
    car_names = []
    car_specs.each_key do |company_name|
      car_specs[company_name].each do |car_spec|
        car_names.push(car_spec['car_name'])
      end
    end

    @db.transaction do
      car_names.uniq.each do |car_name|
        @db[:car_names].insert(name: car_name)
      end
    end
  end

  def setup_car_types(car_specs)
    car_types = []
    car_specs.each_key do |company_name|
      car_specs[company_name].each do |car_spec|
        car_types.push(car_spec['car_type'])
      end
    end

    @db.transaction do
      car_types.uniq.each do |car_type|
        @db[:car_types].insert(name: car_type)
      end
    end
  end

  def setup_specs(car_specs)
    string_columns = @db.schema(:specs).select { |s|
      s[1][:type] == :string
    }.map { |s| s[0].to_s }

    integer_columns = @db.schema(:specs).select { |s|
      s[1][:type] == :integer
    }.map { |s| s[0].to_s }

    float_columns = @db.schema(:specs).select { |s|
      s[1][:type] == :float
    }.map { |s| s[0].to_s }

    @db.transaction do
      car_specs.each_key do |company_name|
        company_name_code = @db[:company_names].where(
          name: company_name
        ).all[0][:code]

        car_specs[company_name].each do |car_spec|
          car_name_code =
            @db[:car_names].where(name: car_spec['car_name']).all[0][:code]
          car_type_code =
            @db[:car_types].where(name: car_spec['car_type']).all[0][:code]

          string_columns.each { |column_name| car_spec[column_name] ||= 'none' }
          integer_columns.each do |column_name|
            car_spec[column_name] ||= -1
          end
          float_columns.each do |column_name|
            car_spec[column_name] ||= -1
          end

          car_spec.store("company_name_code", company_name_code)
          car_spec.store("car_name_code", car_name_code)
          car_spec.store("car_type_code", car_type_code)
          car_spec.delete("car_name")
          car_spec.delete("car_type")

          @db[:specs].insert(car_spec)
        end
      end
    end
  end

  def setup_stocks(car_specs)
    @db.transaction do
      car_specs.each_key do |company_name|
        car_specs[company_name].each do |car_spec|
          num = rand(0..100)
          @db[:stocks].insert(
            car_name_code: car_spec['car_name_code'],
            grade: car_spec['grade'],
            capacity: car_spec['capacity'],
            num: num
          )
        end
      end
    end
  end

  def setup_terms(terms)
    terms.each do |term|
      @db.transaction do
        @db[:terms].insert(abbrev_name: term[0], formal_name: term[1])
      end
    end
  end
end

if $0 == __FILE__
  db_setup = DBSetup.new
  db_setup.run
end


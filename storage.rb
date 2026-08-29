require "sqlite3"
require "fileutils"



class Storage
	def initialize(root, assets_path, posts_path)
		@root = Pathname.new(root)
		
		@posts = @root.join(posts_path)
		@assets = @root.join(assets_path)
		
		@db = SQLite3::Database.new "blogulator.db"
		create_db_if_not_available
		
		FileUtils.mkdir_p(@posts)
		FileUtils.mkdir_p(@assets)
	end
	
	
	
	private
	def create_db_if_not_available
		puts "Checking if table exists..."
		table = @db.execute <<-SQL
			SELECT name FROM sqlite_master WHERE type='table' AND name='posts';
		SQL
		
		if table==[]
			puts "Table does not exist. Creating..."
			@db.execute <<-SQL
						create table if not exists posts (
							id character(36) primary key,
							slug text
						);
					SQL
			puts "Table created!"
		else
			puts "Table already exixts!"
		end
		puts "Database ready!"
		true
	end
end


if __FILE__ == $0
	puts "Blogulator Storage Test"
	puts "======================="
	puts ""
	
	blogulator_storage = Storage.new(".", "assets", "posts")
end
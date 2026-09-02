require "sqlite3"
require "fileutils"
require 'securerandom'
require "time"
require "yaml"
require_relative "utils"
require_relative "posts"



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
	
	
	# Posts
	def create_post(post)
		puts "Creating post #{post.id}..."
		
		directory = @posts.join(post.filepath)
		FileUtils.mkdir_p(directory)
		
		
		post.slug = Utils.unique_slug(directory, post.slug)
		filepath = directory.join(post.slug + ".md")
		
		File.write(filepath, post.to_file)
		
		@db.execute(
			<<~SQL,
				INSERT INTO posts (
					id,
					slug,
					created_at,
					updated_at
				)
				VALUES (?, ?, ?, ?)
			SQL
			[post.id,
			post.slug,
			post.date.iso8601,
			post.date.iso8601]
		)
		
		post.created_at = post.date
		post.updated_at = post.date
		
		puts "Done!"
		
		post.id
	end
	
	def update_post(id, updated_post)
		puts "Updating post #{id}..."

		post = get_post(id)
		return nil unless post

		post.title = updated_post.title if updated_post.title
		post.body = updated_post.body if updated_post.body
		post.updated_at = updated_post.updated_at || Time.now

		directory = @posts.join(post.filepath)
		filepath = directory.join(post.slug + ".md")

		File.write(filepath, post.to_file)

		@db.execute(
			<<~SQL,
				UPDATE posts
				SET slug = ?, updated_at = ?
				WHERE id = ?
			SQL
			[post.updated_at.iso8601,
			id]
		)

		puts "Done!"

		id
	end
	
	def get_post(id)
		post_record = @db.get_first_row(
			"SELECT id, slug, created_at, updated_at FROM posts WHERE id = ?",
			[id]
		)

		return nil unless post_record

		post_id = post_record[0]
		slug = post_record[1]
		created_at = Time.parse(post_record[2])
		updated_at = Time.parse(post_record[3])

		path = @posts
			.join(created_at.strftime("%Y"))
			.join(created_at.strftime("%m"))
			.join(created_at.strftime("%d"))
			.join("#{slug}.md")

		return nil unless File.file?(path)

		content = File.read(path)

		unless content.start_with?("---")
			raise "Post #{id} has invalid Jekyll front matter"
		end

		_, front_matter, body = content.split(/^---\s*$\n/, 3)

		metadata = YAML.safe_load(front_matter, permitted_classes: [Time]) || {}

		Post.new(
			id: post_id,
			title: metadata["title"],
			body: body,
			slug: slug,
			date: metadata["date"],
			created_at: created_at,
			updated_at: updated_at,
			path: path
		)
	end
	
	def delete_post(id)
		puts "Deleting post #{id}..."

		post = get_post(id)
		return false unless post

		if File.file?(post.path)
			File.delete(post.path)
		end
          
		@db.execute(
			"DELETE FROM posts WHERE id = ?",
			[id]
		)
          
		puts "Done!"
          
		true
	end
	
	def post_exists?(id)
		@db.get_first_value(
			"SELECT 1 FROM posts WHERE id = ? LIMIT 1",
			[id]
		) != nil
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
			CREATE TABLE IF NOT EXISTS posts (
				id TEXT PRIMARY KEY,
				slug TEXT NOT NULL,
				created_at TEXT NOT NULL,
				updated_at TEXT NOT NULL
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
	
	
	# Test post CRUD
	puts "> Testing post creation..."
	test_uuid = SecureRandom.uuid
	test_post_title = "Test Post!"
	
	post = Post.new(
		id: test_uuid,
		title: test_post_title,
		body: "Test post content.",
		slug: Utils.slugify(test_post_title),
		date: Time.now,
		created_at: nil,
		updated_at: nil,
	)
	blogulator_storage.create_post(post)
	
	puts "> Testing duplicate post creation..."
	
	test_uuid = SecureRandom.uuid
	
	post = Post.new(
		id: test_uuid,
		title: test_post_title,
		body: "Test post content, duplicate post.",
		slug: Utils.slugify(test_post_title),
		date: Time.now,
		created_at: nil,
		updated_at: nil,
	)
	blogulator_storage.create_post(post)
	
	
	
	
	
	
	
	
	puts "> Done."
	puts "======================="
	
	
	
	
	
	

	test_uuid = SecureRandom.uuid
	test_post_title = "Get post"
	
	post = Post.new(
		id: test_uuid,
		title: test_post_title,
		body: "Test post content.",
		slug: Utils.slugify(test_post_title),
		date: Time.now,
		created_at: nil,
		updated_at: nil,
	)
	blogulator_storage.create_post(post)
	puts "> Testing post retrieval, known id (should be post)..."
	post = blogulator_storage.get_post(test_uuid)
	puts post.inspect
	
	puts "> Testing post retrieval, unknown id (should be nil)..."
	post = blogulator_storage.get_post(SecureRandom.uuid)
	puts post.inspect
	
	puts "> Done."
	puts "======================="






	test_uuid = SecureRandom.uuid
	test_post_title = "Update test"
	post = Post.new(
		id: test_uuid,
		title: test_post_title,
		body: "Test post content.",
		slug: Utils.slugify(test_post_title),
		date: Time.now,
		created_at: nil,
		updated_at: nil,
	)
	blogulator_storage.create_post(post)
	
	puts "> Testing post update..."
	post = Post.new(
		id: test_uuid,
		body: "Test post content, updated.",
		updated_at: Time.now,
	)
	blogulator_storage.update_post(test_uuid, post)
	
	puts post.inspect
	
	puts "> Done."
	puts "======================="
	
	
	
	
	
	
	
	

	test_uuid = SecureRandom.uuid
	test_post_title = "Deletion test"
	post = Post.new(
		id: test_uuid,
		title: test_post_title,
		body: "Test post content.",
		slug: Utils.slugify(test_post_title),
		date: Time.now,
		created_at: nil,
		updated_at: nil,
	)
	blogulator_storage.create_post(post)
	
	puts "> Testing post deletion, known id (should be post)..."
	post = blogulator_storage.delete_post(test_uuid)
	puts post.inspect
	
	puts "> Testing post deletion, unknown id (should be false)..."
	post = blogulator_storage.delete_post(SecureRandom.uuid)
	puts post.inspect
	
	puts "> Done."
	puts "======================="
end
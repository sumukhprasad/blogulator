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
		
		@db = SQLite3::Database.new @root.join($blog_name+"-blogulator.db").to_s
		create_db_if_not_available
		
		FileUtils.mkdir_p(@posts)
		FileUtils.mkdir_p(@assets)
		
		config = YAML.load_file($blog_name+"-blogulator.yml")
		@blog_options = config["blog_options"] || {}
	end
	
	
	
	
	
	def create_post(post)
		puts "Creating post #{post.id}..."

		directory = @posts.join(post.filepath)
		FileUtils.mkdir_p(directory)
		
		if post.slug == ""
			micropost_title = post.body.split.first(5).join(" ")
			post.slug = Utils.slugify(micropost_title)
		end
		
		post.slug = Utils.unique_slug(directory, post.slug)
		filepath = directory.join(post.slug + ".md")

		post.created_at ||= Time.now
		post.updated_at ||= post.created_at

		File.write(
			filepath,
			post.to_file(@blog_options)
		)

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
			[
				post.id,
				post.slug,
				post.created_at.iso8601,
				post.updated_at.iso8601
			]
		)

		puts "Done!"

		post
	end

	def update_post(id, updated_post)
		puts "Updating post #{id}..."

		post = get_post(id)
		return nil unless post

		unless updated_post.title.nil?
			post.title = updated_post.title
			post.metadata["title"] = updated_post.title
		end
		post.body = updated_post.body unless updated_post.body.nil?
		post.updated_at = updated_post.updated_at unless updated_post.updated_at.nil?

		post.metadata = post.metadata.merge(updated_post.metadata || {})

		post.updated_at = updated_post.updated_at || Time.now

		directory = @posts.join(post.filepath)
		FileUtils.mkdir_p(directory)

		filepath = directory.join(post.slug + ".md")
		
		File.write(
			filepath,
			post.to_file(@blog_options)
		)

		@db.execute(
			<<~SQL,
				UPDATE posts
				SET slug = ?, updated_at = ?
				WHERE id = ?
			SQL
			[
				post.slug,
				post.updated_at.iso8601,
				id
			]
		)

		puts "Done!"

		post
	end
	
	def get_post(id)
		post_record = @db.get_first_row(
			"SELECT id, slug, created_at, updated_at FROM posts WHERE id = ?",
			[id]
		)

		return nil unless post_record

		post_id, slug, created_at_string, updated_at_string = post_record

		created_at = Time.parse(created_at_string)
		updated_at = Time.parse(updated_at_string)

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

		unless front_matter && body
			raise "Post #{id} has invalid Jekyll front matter"
		end

		metadata = YAML.safe_load(
			front_matter,
			permitted_classes: [Time, Date]
		) || {}
		
		
		metadata = metadata.except(
		  "id",
		  "body",
		  "slug",
		  "created_at",
		  "updated_at",
		  "path"
		)

		Post.new(
			id: post_id,
			title: metadata["title"],
			body: body,
			slug: slug,
			date: metadata["date"],
			created_at: created_at,
			updated_at: updated_at,
			path: path,
			metadata: metadata
		)
	end
	
	def get_posts(options = {})
		limit = Integer(options.fetch(:limit, 20))
		offset = Integer(options.fetch(:offset, 0))

		rows = @db.execute(
			<<~SQL,
				SELECT id, slug, created_at, updated_at
				FROM posts
				ORDER BY created_at DESC
				LIMIT ? OFFSET ?
			SQL
			[
				limit,
				offset
			]
		)

		rows.filter_map do |row|
			id, slug, created_at_string, updated_at_string = row

			created_at = Time.parse(created_at_string)
			updated_at = Time.parse(updated_at_string)

			path = @posts
				.join(created_at.strftime("%Y"))
				.join(created_at.strftime("%m"))
				.join(created_at.strftime("%d"))
				.join("#{slug}.md")

			unless File.file?(path)
				warn "Skipping post #{id}: file not found at #{path}"
				next
			end

			content = File.read(path)

			unless content.start_with?("---")
				warn "Skipping post #{id}: invalid Jekyll front matter"
				next
			end

			_, front_matter, body = content.split(/^---\s*$\n/, 3)

			unless front_matter && body
				warn "Skipping post #{id}: invalid Jekyll front matter"
				next
			end

			metadata = YAML.safe_load(
				front_matter,
				permitted_classes: [Time, Date]
			) || {}
			
			metadata = metadata.except(
			  "id",
			  "body",
			  "slug",
			  "created_at",
			  "updated_at",
			  "path"
			)

			Post.new(
				id: id,
				title: metadata["title"],
				body: body,
				slug: slug,
				date: metadata["date"],
				created_at: created_at,
				updated_at: updated_at,
				path: path,
				metadata: metadata
			)
		end
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
	
	
	
	
	
	
	
	
	
	
	# Media
	def create_media(filename:, content_type:, data:)
		id = SecureRandom.uuid
		now = Time.now

		original_filename = filename
		filename = Utils.sanitize_filename(filename)

		directory = @assets
				.join(now.strftime("%Y"))
				.join(now.strftime("%m"))
				.join(now.strftime("%d"))

		FileUtils.mkdir_p(directory)

		path = directory.join(Utils.get_unique_filename(directory, filename))

		File.binwrite(path, data)

		@db.execute(
			<<~SQL,
				INSERT INTO media (
					id,
					filename,
					original_filename,
					content_type,
					size,
					created_at,
					updated_at
				)
				VALUES (?, ?, ?, ?, ?, ?, ?)
			SQL
			[
				id,
				filename,
				original_filename,
				content_type,
				data.bytesize,
				now.iso8601,
				now.iso8601
			]
		)

		Media.new(
			id: id,
			filename: filename,
			original_filename: filename,
			content_type: content_type,
			size: data.bytesize,
			created_at: now,
			updated_at: now,
			path: path
		)
	end
	
	def get_media(id)
		row = @db.get_first_row(
			<<~SQL,
				SELECT
					id,
					filename,
					original_filename,
					content_type,
					size,
					created_at,
					updated_at
				FROM media
				WHERE id = ?
			SQL
			[id]
		)

		return nil unless row

		id,
		filename,
		original_filename,
		content_type,
		size,
		created_at,
		updated_at = row

		created_at = Time.parse(created_at)

		path = @assets
				.join(created_at.strftime("%Y"))
				.join(created_at.strftime("%m"))
				.join(created_at.strftime("%d"))
				.join(filename)

		return nil unless File.file?(path)

		Media.new(
			id: id,
			filename: filename,
			original_filename: original_filename,
			content_type: content_type,
			size: size,
			created_at: created_at,
			updated_at: created_at,
			path: path
		)
	end
	
	def get_media_content(id)
		media = get_media(id)
		return nil unless media

		File.binread(media.path)
	end

	
	# Helpers
	private
	def create_db_if_not_available
		puts "Checking if posts table exists..."
		posts_table = @db.execute <<-SQL
			SELECT name FROM sqlite_master WHERE type='table' AND name='posts';
		SQL
		
		if posts_table==[]
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
		
		puts "Checking if media table exists..."
		media_table = @db.execute <<-SQL
			SELECT name FROM sqlite_master WHERE type='table' AND name='media';
		SQL
		
		if media_table==[]
			puts "Table does not exist. Creating..."
			@db.execute <<-SQL
			CREATE TABLE IF NOT EXISTS media (
				id TEXT PRIMARY KEY,
				filename TEXT NOT NULL,
				original_filename TEXT,
				content_type TEXT NOT NULL,
				size INTEGER NOT NULL,
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
	
	puts "> Testing post retrieval, multiple..."
	posts = blogulator_storage.get_posts()
	puts posts.inspect
	
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
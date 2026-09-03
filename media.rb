Media = Struct.new(
    :id,
    :filename,
    :original_filename,
    :content_type,
    :size,
    :created_at,
    :updated_at,
    :path,
    keyword_init: true
)
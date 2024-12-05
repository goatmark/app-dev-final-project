# app/services/notion_client_extension.rb


module NotionClientExtension
  # Define a method to fetch children blocks
  def blocks_children_list(block_id:, start_cursor: nil, page_size: 100)
    response = @connection.get("/blocks/#{block_id}/children") do |req|
      req.headers['Authorization'] = "Bearer #{@token}"
      req.headers['Notion-Version'] = '2022-06-28' # Use the appropriate Notion API version
      req.params['start_cursor'] = start_cursor if start_cursor
      req.params['page_size'] = page_size
    end

    handle_response(response)
  end
end

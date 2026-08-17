class Assistant::Function::GetMerchants < Assistant::Function
  class << self
    def default_page_size
      50
    end

    def name
      "get_merchants"
    end

    def description
      <<~INSTRUCTIONS
        Returns merchants defined for the user's family, sorted alphabetically, with pagination.

        Use this when the user wants to see available merchants or before referencing
        a merchant in another operation like update_merchant or delete_merchant.

        Note on pagination:

        This function can be paginated. You can expect the following properties in the response:

        - `total_pages`: The total number of pages of results
        - `page`: The current page of results
        - `page_size`: The number of results per page (this will always be #{default_page_size})
        - `total_results`: The total number of results
      INSTRUCTIONS
    end
  end

  def params_schema
    build_schema(
      required: [],
      properties: {
        page: {
          type: "integer",
          description: "Page number (defaults to 1)"
        }
      }
    )
  end

  def call(params = {})
    merchants_scope = family.merchants.alphabetically
    pagy = Pagy.new(count: merchants_scope.count, page: params["page"] || 1, limit: default_page_size)
    merchants = merchants_scope.offset(pagy.offset).limit(pagy.limit)

    {
      merchants: merchants.map { |m| { id: m.id, name: m.name, color: m.color, website_url: m.website_url } },
      total_results: pagy.count,
      page: pagy.page,
      page_size: default_page_size,
      total_pages: pagy.pages
    }
  end

  private
    def default_page_size
      self.class.default_page_size
    end
end

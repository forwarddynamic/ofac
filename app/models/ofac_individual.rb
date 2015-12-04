class OfacIndividual


  # Accepts a hash with the identity's demographic information
  #
  #   OfacIndividual.new({:name => 'Oscar Hernandez', :city => 'Clearwater', :address => '123 somewhere ln'})
  #
  # <tt>:name</tt> is required to get a score.  If <tt>:name</tt> is missing, an error will not be thrown, but a score of 0 will be returned.
  #
  # You can pass a string in for the full name:
  #   OfacIndividual.new(:name => 'Victor De La Garza')
  #
  # Or you can specify the last and first names
  #   OfacIndividual.new(:name => {:first_name => 'Victor', :last_name => 'De La Garza'})
  #
  # The first method will build a larger list of names for ruby to parse through and more likely to find similar names.
  # The second method is quicker.
  #
  # The more information provided, the higher the score could be.  A score of 100 would mean all fields
  # were passed in, and all fields were 100% matches.  If only the name is passed in without an address,
  # it will be impossible to get a score of 100, even if the name matches perfectly.
  #
  # Acceptable hash keys and their weighting in score calculation:
  #
  # * <tt>:name</tt> (weighting = 60%) (required) This must be a person
  # * <tt>:address</tt> (weighting = 10%)
  # * <tt>:city</tt> (weighting = 30%)
  def initialize(identity)
    @identity = identity
  end

  # Creates a score, 1 - 100, based on how well the name and address match the data on the
  # SDN (Specially Designated Nationals) list.
  #
  # The score is calculated by adding up the weightings of each part that is matched. So
  # if only name is matched, then the max score is the weight for <tt>:name</tt> which is 60
  #
  # It's possible to get partial matches, which will add partial weight to the score.  If there
  # is not a match on the element as it is passed in, then each word element gets broken down
  # and matches are tried on each partial element.  The weighting is distrubuted equally for
  # each partial that is matched.
  #
  # If exact matches are not made, then a sounds like match is attempted.  Any match made by sounds like
  # is given 75% of it's weight to the score.
  #
  # Example:
  #
  # If you are trying to match the name Kevin Tyll and there is a record for Smith, Kevin in the database, then
  # we will try to match both Kevin and Tyll separately, with each element Smith and Kevin.  Since only Kevin
  # will find a match, and there were 2 elements in the searched name, the score will be added by half the weighting
  # for <tt>:name</tt>.  So since the weight for <tt>:name</tt> is 60, then we will add 30 to the score.
  #
  # If you are trying to match the name Kevin Gregory Tyll and there is a record for Tyll, Kevin in the database, then
  # we will try to match Kevin and Gregory and Tyll separately, with each element Tyll and Kevin.  Since both Kevin
  # and Tyll will find a match, and there were 3 elements in the searched name, the score will be added by 2/3 the weighting
  # for <tt>:name</tt>.  So since the weight for <tt>:name</tt> is 60, then we will add 40 to the score.
  #
  # If you are trying to match the name Kevin Tyll and there is a record for Kevin Gregory Tyll in the database, then
  # we will try to match Kevin and Tyll separately, with each element Tyll and Kevin and Gregory.  Since both Kevin
  # and Tyll will find a match, and there were 2 elements in the searched name, the score will be added by 2/2 the weighting
  # for <tt>:name</tt>.  So since the weight for <tt>:name</tt> is 60, then we will add 60 to the score.
  #
  # If you are trying to match the name Kevin Tyll, and there is a record for Teel, Kevin in the database, then an exact match
  # will be found for Kevin, and a sounds like match will be made for Tyll.  Since there were 2 elements in the searched name,
  # and the weight for <tt>:name</tt> is 60, then each element is worth 30.  Since Kevin was an exact match, it will add 30, and
  # since Tyll was a sounds like match, it will add 30 * .75.  So the <tt>:name</tt> portion of the search will be worth 53.
  #
  # If data is in the database for city and or address, and you pass data in for these elements, the score will be reduced by 10%
  # of the weight if there is no match or sounds like match.  So if you get a match on name, you've already got a score of 60.  So
  # if you don't pass in an address or city, or if you do, but there is no city or address info in the database, then your final score
  # will be 60.  But if you do pass in a city, say Tampa, and the city in the Database is New York, then we will deduct 10% of the
  # weight (30 * .1) = 3 from the score since 30 is the weight for <tt>:city</tt>.  So the final score will be 57.
  #
  # If were searching for New York, and the database had New Deli, then there would be a match on New, but not on Deli.
  # Since there were 2 elements in the searched city, each hit is worth 15.  So the match on New would add 15, but the non-match
  # on York would subtract (15 * .1) = 1.5 from the score.  So the score would be (60 + 15 - 1.5) = 74, due to rounding.
  #
  # Only <tt>:city</tt> and <tt>:address</tt> subtract from the score, No match on name simply returns 0.
  #
  # Matches for name are made for both the name and any aliases in the OFAC database.
  #
  # Matches for <tt>:city</tt> and <tt>:address</tt> will only be added to the score if there is first a match on <tt>:name</tt>.
  #
  # We consider a score of 60 to be reasonable as a hit.
  def score
    @score || calculate_score
  end

  def db_hit?
    unless @identity[:name].to_s.blank?

      #first get a list from the database of possible matches by name
      #this query is pretty liberal, we just want to get a list of possible
      #matches from the database that we can run through our ruby matching algorithm
      hit = false
      name_array = process_name

      name_array.delete_if{|n| n.strip.size < 2}
      unless name_array.empty?
        hit = OfacSdnIndividual.possible_sdns(name_array).exists?
      end
    end
    hit
  end

  # Returns an array of hashes of records in the OFAC data that found partial matches with that record's score.
  #
  #     OfacIndividual.new({:name => 'Oscar Hernandez', :city => 'Clearwater', :address => '123 somewhere ln'}).possible_hits
  #returns
  #     [{:address=>"123 Somewhere Ln", :score=>100, :name=>"HERNANDEZ, Oscar|GUAMATUR, S.A.", :city=>"Clearwater"}, {:address=>"123 Somewhere Ln", :score=>100, :name=>"HERNANDEZ, Oscar|Alternate Name", :city=>"Clearwater"}]
  #
  def possible_hits
    @possible_hits || retrieve_possible_hits
  end

  private

  def retrieve_possible_hits
    score
    @possible_hits
  end

  def calculate_score
    unless @identity[:name].to_s.blank?

      #first get a list from the database of possible matches by name
      #this query is pretty liberal, we just want to get a list of possible
      #matches from the database that we can run through our ruby matching algorithm

      name_array = process_name

      name_array.delete_if{|n| n.strip.size < 2}
      unless name_array.empty?
        possible_sdns = OfacSdnIndividual.possible_sdns(name_array, use_ors = true)
        possible_sdns = possible_sdns.collect {|sdn|{:name => "#{sdn.name}|#{sdn.alternate_identity_name}", :city => sdn.city, :address => sdn.address}}

        match = OfacMatch.new({:name => {:weight => 90, :token => "#{name_array.join(', ')}"},
            :address => {:weight => 5, :token => @identity[:address]},
            :city => {:weight => 5, :token => @identity[:city]}})

        score = match.score(possible_sdns)
        @possible_hits = match.possible_hits
      end
    end
    @score = score || 0
    return @score
  end

  def process_name
    #you can pass in a full name, or specify the first and last name
    if @identity[:name].kind_of?(Hash)
      (@identity[:name][:last_name].to_s.upcase.gsub(/[[:punct:]]/, '').split(/\W/) + @identity[:name][:first_name].to_s.upcase.gsub(/[[:punct:]]/, '').split(/\W/)).compact
    else
      @identity[:name].to_s.upcase.gsub(/[[:punct:]]/, '').split(/\W/).reverse
    end
  end
end

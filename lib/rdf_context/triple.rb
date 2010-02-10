require File.join(File.dirname(__FILE__), 'bnode')
require File.join(File.dirname(__FILE__), 'literal')
require File.join(File.dirname(__FILE__), 'uriref')

module RdfContext
  # An RDF Triple, or statement.
  #
  # Statements are composed of _subjects_, _predicates_ and _objects_.
  class Triple
    attr_accessor :subject, :object, :predicate

    ##
    # Creates a new triple directly from the intended subject, predicate, and object.
    #
    # Any or all of _subject_, _predicate_ or _object_ may be nil, to create a triple pattern.
    # A pattern may not be added to a graph.
    #
    # ==== Example
    #   Triple.new(BNode.new, URIRef.new("http://xmlns.com/foaf/0.1/knows"), BNode.new) # => results in the creation of a new triple and returns it
    #
    # @param [URIRef, BNode] subject:: the subject of the triple
    # @param [URIRef] predicate:: the predicate of the triple
    # @param [URIRef, BNode, Literal, TypedLiteral] object:: the object of the triple
    # @return [Triple]:: Generated triple
    # @raise [Error]:: Checks parameter types and raises if they are incorrect.
    #
    # @author Tom Morris
    def initialize (subject, predicate, object)
      @subject   = self.class.coerce_node(subject)
      @predicate = self.class.coerce_predicate(predicate)
      @object    = self.class.coerce_node(object)
      @pattern = subject.nil? || predicate.nil? || object.nil?
    end

    def is_pattern?
      @pattern
    end
    
    # Serialize Triple to N3
    def to_n3
      raise RdfException.new("Can't serialize pattern triple '#{@subject.inspect}, #{@predicate.inspect}, #{@object.inspect}'") if is_pattern?
      @subject.to_ntriples + " " + @predicate.to_ntriples + " " + @object.to_ntriples + " ."
    end
    alias_method :to_ntriples, :to_n3
    
    def to_s; self.to_ntriples; end
    
    def inspect
      "#{self.class}[#{self.to_n3}]"
    end

    # Is the predicate of this statment rdf:type?
    def is_type?
      @predicate.to_s == "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
    end

    # Two triples are equal if their of their subjects, predicates and objects are equal.
    # Or self or other is a pattern and subject, predicate, object matches
    def eql? (other)
      other.is_a?(Triple) &&
      (other.subject == self.subject || other.subject.nil? || self.subject.nil?) &&
      (other.predicate == self.predicate || other.predicate.nil? || self.predicate.nil?) &&
      (other.object == self.object || other.object.nil? || self.object.nil?)
    end

    alias_method :==, :eql?

    # Clone triple, keeping references to literals and URIRefs, but cloning BNodes
    def clone
      raise RdfException.new("Can't clone pattern triple") if is_pattern?
      s = subject.is_a?(BNode) ? subject.clone : subject
      p = predicate.is_a?(BNode) ? predicate.clone : predicate
      o = object.is_a?(BNode) ? object.clone : object
      Triple.new(subject, predicate, object)
    end
    
    # For indexes
    def hash
      [subject, predicate, object].hash
    end
    
    protected

    # Coerce a predicate to the appropriate RdfContext type.
    # 
    # @param[URI, URIRef, String] predicate:: If a String looks like a URI, a URI is created
    # @raise[InvalidPredicate]:: If predicate can't be predicate.
    def self.coerce_predicate(predicate)
      case predicate
      when Addressable::URI
        URIRef.new(predicate.to_s)
      when URIRef
        predicate
      when String
        URIRef.new predicate
      when nil
        predicate
      else
        raise InvalidPredicate, "Predicate should be a URI"
      end
    rescue ParserException => e
      raise InvalidPredicate, "Couldn't make a URIRef: #{e.message}"
    end

    # Coerce a node (subject or object) to the appropriate RdfContext type.
    # 
    # @param[URI, URIRef, String, Integer, Float, BNode, Literal] object:: If a String looks like a URI, a URI is created, otherwise an untyped Literal.
    # @raise[InvalidNode]:: If node can't be predicate.
    def self.coerce_node(node)
      case node
      when Addressable::URI
        URIRef.new(node.to_s)
      when String
        if node.to_s =~ /^\w+:\/\/\S+/ # does it smell like a URI?
          URIRef.new(node.to_s)
        else
          Literal.untyped(node)
        end
      when Numeric, Date, Duration, Time, DateTime
        Literal.build_from(node)
      when URIRef, BNode, Literal, Graph, nil
        node
      else
        raise InvalidNode, "#{node.class}: #{node.inspect} is not a valid node"
      end
    end
  end
end

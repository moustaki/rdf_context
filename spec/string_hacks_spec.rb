# coding: utf-8
require File.join(File.dirname(__FILE__), 'spec_helper')
describe "String RDF encoding" do
  {
    "Gregg" => 'Gregg',
    "Dürst" => 'D\u00FCrst',
    "simple literal"  => 'simple literal',
    "backslash:\\" => 'backslash:\\\\',
    "dquote:\"" => 'dquote:\\"',
    "newline:\n" => 'newline:\\n',
    "return:\r" => 'return:\\r',
    "tab:\t" => 'tab:\\t',
  }.each_pair do |raw, encoded|
    specify "'#{raw}' should escape to '#{encoded}'" do
      raw.rdf_escape.should == encoded
    end

    specify "'#{encoded}' should unescape to '#{raw}'" do
      encoded.rdf_unescape.should == raw
    end
  end
  
  # 16-bit string encodings
  {
    "16-bit:\u{15678}another" => '16-bit:\\U00015678another',
  }.each_pair do |raw, encoded|
    specify "'#{raw}' should escape to '#{encoded}'" do
      raw.rdf_escape.should == encoded
    end

    specify "'#{encoded}' should unescape to '#{raw}'" do
      encoded.rdf_unescape.should == raw
    end
  end if defined?(::Encoding)
end
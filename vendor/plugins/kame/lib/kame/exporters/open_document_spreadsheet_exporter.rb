# Register ODS format unless is already set
Mime::Type.register("application/vnd.oasis.opendocument.spreadsheet", :ods) unless defined? Mime::ODS

module Kame
  
  class OpenDocumentSpreadsheetExporter < Kame::Exporter
    
    DATE_ELEMENTS = {
      "m" => "<number:month number:style=\"long\"/>",
      "d" => "<number:day number:style=\"long\"/>",
      "Y" => "<number:year/>"
    }


    def file_extension
      "ods"
    end

    def mime_type
      Mime::ODS
    end

    def send_data_code(table)

      record = "r"
      code  = Kame::SimpleFinder.new.select_data_code(table)
      code += "name = #{table.model.name}.model_name.human.gsub(/[^a-z0-9]/i,'_')\n"
      code += "file = Rails.root.join('tmp', 'kame'+rand.to_s+'.#{self.file_extension}')\n"
      code += "Zip::ZipOutputStream.open(file) do |zile|\n"
      code += "  zile.put_next_entry('META-INF/manifest.xml')\n"
      code += "  zile.puts('<?xml version=\"1.0\" encoding=\"UTF-8\"?><manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\"><manifest:file-entry manifest:media-type=\"#{self.mime_type}\" manifest:full-path=\"/\"/><manifest:file-entry manifest:media-type=\"text/xml\" manifest:full-path=\"content.xml\"/></manifest:manifest>')\n"
      code += "  zile.put_next_entry('mimetype')\n"
      code += "  zile.puts('#{self.mime_type}')\n"
      code += "  zile.put_next_entry('content.xml')\n"

      code += "  zile.puts('<?xml version=\"1.0\" encoding=\"UTF-8\"?><office:document-content xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\" xmlns:draw=\"urn:oasis:names:tc:opendocument:xmlns:drawing:1.0\" xmlns:fo=\"urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:meta=\"urn:oasis:names:tc:opendocument:xmlns:meta:1.0\" xmlns:number=\"urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0\" xmlns:presentation=\"urn:oasis:names:tc:opendocument:xmlns:presentation:1.0\" xmlns:svg=\"urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0\" xmlns:chart=\"urn:oasis:names:tc:opendocument:xmlns:chart:1.0\" xmlns:dr3d=\"urn:oasis:names:tc:opendocument:xmlns:dr3d:1.0\" xmlns:math=\"http://www.w3.org/1998/Math/MathML\" xmlns:form=\"urn:oasis:names:tc:opendocument:xmlns:form:1.0\" xmlns:script=\"urn:oasis:names:tc:opendocument:xmlns:script:1.0\" xmlns:ooo=\"http://openoffice.org/2004/office\" xmlns:ooow=\"http://openoffice.org/2004/writer\" xmlns:oooc=\"http://openoffice.org/2004/calc\" xmlns:dom=\"http://www.w3.org/2001/xml-events\" xmlns:xforms=\"http://www.w3.org/2002/xforms\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:field=\"urn:openoffice:names:experimental:ooxml-odf-interop:xmlns:field:1.0\" office:version=\"1.1\"><office:scripts/>')\n"
      # Styles
      code += "  zile.puts('<office:automatic-styles>"+
        "<style:style style:name=\"co1\" style:family=\"table-column\"><style:table-column-properties fo:break-before=\"auto\" style:use-optimal-column-width=\"true\"/></style:style>"+
        "<style:style style:name=\"header\" style:family=\"table-cell\"><style:text-properties fo:font-weight=\"bold\" style:font-weight-asian=\"bold\" style:font-weight-complex=\"bold\"/></style:style>"+
        "<number:date-style style:name=\"K4D\" number:automatic-order=\"true\"><number:text>"+::I18n.translate("date.formats.default").gsub(/\%./){|x| "</number:text>"+DATE_ELEMENTS[x[1..1]]+"<number:text>"} +"</number:text></number:date-style><style:style style:name=\"ce1\" style:family=\"table-cell\" style:data-style-name=\"K4D\"/>"+
        "</office:automatic-styles>')\n"

      # Tables
      code += "  zile.puts('<office:body><office:spreadsheet><table:table table:name=\"'+#{table.model.name}.model_name.human+'\">')\n"
      code += "  zile.puts('<table:table-row>"+columns_headers(table).collect{|h| "<table:table-cell table:style-name=\"header\" office:value-type=\"string\"><text:p>'+#{h}+'</text:p></table:table-cell>"}.join+"</table:table-row>')\n"
      code += "  for #{record} in #{table.records_variable_name}\n"  
      code += "    zile.puts('<table:table-row>"+table.exportable_columns.collect do |column|
        "<table:table-cell"+(if column.numeric?
                               " office:value-type=\"float\" office:value=\"'+#{column.datum_code(record)}.to_s+'\""
                             elsif column.datatype==:boolean
                               " office:value-type=\"boolean\" office:boolean-value=\"'+#{column.datum_code(record)}.to_s+'\""
                             elsif column.datatype==:date
                               " office:value-type=\"date\" table:style-name=\"ce1\" office:date-value=\"'+#{column.datum_code(record)}.to_s+'\""
                             else 
                               " office:value-type=\"string\""
                             end)+"><text:p>'+"+column.exporting_datum_code(record)+".to_s+'</text:p></table:table-cell>"
      end.join+"</table:table-row>')\n"
      code += "  end\n"
      code += "  zile.puts('</table:table></office:spreadsheet></office:body></office:document-content>')\n"
      code += "end\n"
      code += "send_file(file, :type=>#{self.mime_type.to_s.inspect}, :disposition=>'inline', :filename=>name+'.#{self.file_extension}')\n"
      return code
    end

  end

end

Kame.register_exporter(:ods, Kame::OpenDocumentSpreadsheetExporter)

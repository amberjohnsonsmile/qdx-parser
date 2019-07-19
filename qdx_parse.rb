require 'csv'
require 'time'
require 'active_support'
require 'active_support/core_ext'
require 'pry'
require './qdx_fields'

module Qdx
  QdxTicket = Struct.new("QdxTicket", :line_items, :loyaltycard, :purchase_time,
                         :account_number, :store_id, :ticket_id, :total,
                         :terminal_id, :transaction_id,
                         :tax_value, :item_count, :discounts, :coupons)

  QdxLineItem = Struct.new("QdxLineItem", :upc, :quantity, :price, :amount, :datetime)
  QdxDiscountItem = Struct.new("QdxDiscountItem", :upc, :quantity, :price, :amount, :discount_type, :datetime)
  QdxCouponItem = Struct.new("QdxCouponItem", :coupon_code, :quantity, :amount, :datetime)

  class QdxParse

    OPCODES = {
      '01' => :line_item,
      # '02' => :dept_item,
      '03' => :discount,
      '04' => :payment,
      '05' => :total,
      # '06' => :tax,
      # '08' => :coupon,
      # '21' => :ticket_frame,
      # '50' => :transaction_frame,
      '60' => {
        '1B' => :clubcard,
        '31' => :location,
      },
    }

    TAIL_DATA_PROTO = QdxFields::TailData.new
    LINE_ITEM_PROTO = QdxFields::LineItem.new
    CLUB_DATA_PROTO = QdxFields::Clubcard.new
    PAYMENT_DATA_PROTO = QdxFields::Payment.new
    LOCATION_DATA_PROTO = QdxFields::Location.new
    TOTAL_DATA_PROTO = QdxFields::Total.new
    DISCOUNT_DATA_PROTO = QdxFields::Discount.new
    COUPON_DATA_PROTO = QdxFields::Coupon.new

    attr_accessor :file, :callback_block, :tickets, :tail_data_proto, :line_item_proto
    attr_accessor :club_data_proto, :payment_data_proto, :location_data_proto, :total_data_proto

    attr_accessor :saved, :done, :debug, :count, :index, :line_callback, :with_loyalty_only

    def initialize(infile, with_loyalty_only: true, &block)
      # default to printing csv
      self.callback_block = block || lambda { |ticket| self.process_ticket(ticket) }
      self.with_loyalty_only = with_loyalty_only

      self.tickets = Hash.new do |hash, key|
        ticket = QdxTicket.new
        ticket.line_items = []
        ticket.discounts = []
        ticket.coupons = []
        hash[key] = ticket
      end
      # use prototype pattern for these fields

      #useful debugging values for getting data of interest
      self.saved = []
      self.line_callback = nil
      self.count = 0
      self.done = false

      self.file = if infile.is_a? String
                    File.open(infile, 'rb')
                  elsif infile.respond_to? :each_line
                    infile
                  end
    end

    #todo fsm for line receipt

    def parse(&block)
      # override block
      if block
        orig_block = self.callback_block
        self.callback_block = block
      end

      self.index = -1
      until file.eof? || self.done
        self.index += 1
        line = file.read(64)

        tail = line[44, 20]
        tail_data = tail ? parse_tail(tail) : {}

        parse_line(line, tail_data)
      end
      self.callback_block = orig_block if orig_block
      self.saved if self.debug || self.done
    end

    def parse_tail(tail)
      #page 5
      TAIL_DATA_PROTO.new.read(tail)
    end

    def parse_line(line, tail_data)
      # self.saved += line
      #page 2
      self.line_callback.call(line, tail_data) if self.line_callback
      opcode = line[0, 1].unpack("H*")
      op = OPCODES[opcode[0].upcase] if opcode
      if op.is_a? Symbol
        self.send(op, line, tail_data)
      elsif op.is_a? Hash
        subopcodearray = line[1, 1].unpack('H*')
        subopcode = subopcodearray[0] if subopcodearray
        subop = op[subopcode.upcase]
        if subop.is_a? Symbol
          self.send(subop, line, tail_data)
        end
      end
    end

    def ticket_identifier(tail_data)
      "#{tail_data.pos_number}_#{tail_data.ticket_number}"
    end

    def line_item(line, tail_data)
      # using prototype pattern is faster than new-upping from scratch
      # and avoids needing to dup values
      line_data = LINE_ITEM_PROTO.new
      line_data.read(line)

      data = QdxLineItem.new(line_data.upc.to_s, line_data.quantity.to_i, line_data.price.to_i,
                             line_data.amount.to_i, tail_data.time)

      self.tickets[self.ticket_identifier(tail_data)].line_items << data
    end

    def clubcard(line, tail_data)
      self.tickets[self.ticket_identifier(tail_data)].loyaltycard = CLUB_DATA_PROTO.new.read(line).card_no.to_s
    end

    def payment(line, tail_data)
      self.tickets[self.ticket_identifier(tail_data)].account_number = PAYMENT_DATA_PROTO.new.read(line).account.to_s
    end

    def location(line, tail_data)
      self.tickets[self.ticket_identifier(tail_data)].store_id = LOCATION_DATA_PROTO.new.read(line).store_id.to_s
    end

    def discount(line, tail_data)
      line_data = DISCOUNT_DATA_PROTO.new
      line_data.read(line)
      discount_item = QdxDiscountItem.new(line_data.upc.to_s, line_data.quantity, line_data.price.to_i, line_data.amount.to_i, line_data.type_flags, tail_data.time)
      self.tickets[self.ticket_identifier(tail_data)].discounts << discount_item
    end

    def coupon(line, tail_data)
      line_data = COUPON_DATA_PROTO.new
      line_data.read(line)
      coupon_item = QdxCouponItem.new(line_data.code.to_s, line_data.quantity.to_i, line_data.amount.to_i, tail_data.time)
      self.tickets[self.ticket_identifier(tail_data)].coupons << coupon_item
    end

    # def tax(line, tail_data)
    #   self.tickets[self.ticket_identifier(tail_data)].raw_tax << line
    # end

    def total(line, tail_data)
      ticket_id = self.ticket_identifier(tail_data)
      ticket = self.tickets[ticket_id]
      self.tickets.delete(ticket_id)

      return nil if self.with_loyalty_only && ticket.loyaltycard.blank?

      ticket.ticket_id = ticket_id
      ticket.terminal_id = tail_data.pos_number
      ticket.transaction_id = tail_data.ticket_number

      total = new_total_data.read(line)

      return nil if total.voided_ticket == 1
      ticket.total = total.amount
      ticket.tax_value = total.tax_value
      ticket.item_count = total.item_count
      return nil if ticket.item_count == 0
      return nil if ticket.total > 1000000 # bad bits
      ticket.purchase_time = tail_data.time

      self.callback_block.call(ticket)
    end

    def new_total_data
      TOTAL_DATA_PROTO.new
    end

    def process_ticket(ticket)
      options = {
        col_sep: '|',
        headers: [:store_id, :ticket_id, :card_id, :date, :upc, :quantity, :price, :cc, :total]
      }
      csv_string = CSV.generate('', options) do |csv|
        ticket.line_items.each do |item|
          csv << [ticket[:store_id], ticket[:ticket_id], ticket[:loyaltycard], item[:datetime], item[:upc], item[:quantity], item[:price], ticket[:account_number], ticket[:total]]
        end
      end
      puts csv_string
    end

    def method_missing(m, *args, &block)
      # line, tail_data = args
      # puts "CALLED: #{m}", tail_data
    end

  end
end

def parse()
  begin
    file = ARGV[0]
    tickets = []

    parser = Qdx::QdxParse.new(file) { |ticket| tickets << ticket }
    parser.parse

    CSV.open("#{file[0...-4]}.csv", "wb") do |csv|
      csv << tickets[0].members # adds the attributes name on the first line
      tickets.each do |hash|
        csv << hash.to_a
      end
    end
    puts "File successfully parsed as #{file[0...-4]}.csv"
  rescue => e
    puts "Could not parse file. Error: #{e.message}"
  end
end

parse()

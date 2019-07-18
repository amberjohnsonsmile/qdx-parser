require 'bindata'

module Qdx
  module QdxFields
    class BcdDateTime < BinData::Record
      bit4 :year1
      bit4 :year2
      bit4 :month1
      bit4 :month2
      bit4 :day1
      bit4 :day2
      bit4 :hour1
      bit4 :hour2
      bit4 :minute1
      bit4 :minute2
      bit4 :second1
      bit4 :second2

      def time
        if @datetime.nil?
          begin
            @datetime = Time.local(
              self.year1 * 10+1900 + self.year2,
              self.month1 * 10 + self.month2,
              self.day1 * 10 + self.day2,
              self.hour1 * 10 + self.hour2,
              self.minute1 * 10 + self.minute2,
              self.second1 * 10 + self.second2
            )
          rescue ArgumentError
            Rails.logger.error("Bad BcdDateTime: #{self.inspect}")
            @datetime = Time.now
          end
        end
        @datetime
      end
      def clear
        @datetime = nil
        super()
      end
    end

    class TailData < BinData::Record
      endian :little

      bit8 :seq2
      bit8 :flag
      bit8 :external_pos_number
      bit8 :flag_options
      uint16 :ticket_number
      bcd_date_time :raw_datetime
      bit8 :options
      uint16 :cashier_number
      uint8 :pos_number
      uint16 :seq_no
      bit8 :pc_no_tv_no
      bit8 :unused_zero

      ##
      # provide a clean Time representation of the underlying bcd datetime
      delegate :time, to: :raw_datetime
    end

    class LineItem < BinData::Record
      endian :little

      uint8 :opcode
      #TODO: write a BCD dynamic primitive type (similar to :uint#)
      string :code, :read_length => 7
      bit8 :flag1
      bit8 :flag2
      bit8 :flag3
      bit8 :flag4
      bit8 :flag5
      uint16 :department_number
      uint8 :multi_sell_unit
      uint8 :return_type
      uint8 :tax_pointer
      int32 :quantity
      uint32 :price
      uint32 :amount
      uint32 :no_tax_price
      uint32 :no_tax_amount
      float :return_surcharge_percent
      uint8 :product_code
      bit8 :flags

      def upc
        self.code.unpack("H*").first
      end
    end

    class Clubcard < BinData::Record
      endian :little

      uint8 :opcode
      uint8 :function
      bit8 :flag1
      uint8 :scheme_no
      string :card_no, :read_length => 20, :trim_padding => true
      # TODO: the rest here if necessary
    end

    class Payment < BinData::Record
      endian :little

      uint8 :opcode
      uint16 :media
      bit8 :flag1
      bit8 :flag2
      bit8 :flag3
      bit8 :flag4
      uint8 :type_field # not sure on type of this field, but it's just 1 byte
      uint32 :amount
      uint32 :foreign_amount
      uint32 :foreign_rate
      uint16 :issue_date #no idea how this is stored, 2 bytes

      # another candidate bcd type field
      string :account_number, :read_length => 10 # cc number
      # TODO: the rest as needed

      ##
      # Extract the final 4 digits of account number from payment data
      def account
          self.account_number[-2, 2].unpack("H*").first
      end

    end

    class Location < BinData::Record
      endian :little

      uint8 :opcode
      uint8 :subopcode
      bit8 :flag1
      string :store_id, :read_length => 6
      # TODO the rest
    end

    class Total < BinData::Record
      endian :little

      uint8 :opcode
      #Flag 1 flags
      bit1 :ticket_total
      bit1 :voided_ticket
      bit1 :saved_ticket
      bit1 :recalled_transaction
      bit1 :drive_off
      bit1 :quick_store
      bit1 :pc_info
      bit1 :tender_purchase

      bit8 :flag2
      uint16 :ticket_number
      uint32 :tax_value
      uint16 :item_count
      uint32 :amount
      # TODO: the rest
    end

    class Discount < BinData::Record
      endian :little

      uint8 :opcode
      #TODO: write a BCD dynamic primitive type (similar to :uint#)
      string :item_code, :read_length => 7 #if discount on item

      uint16 :department_number

      string :flag_1, :read_length => 1
      #Flag 1 flags
      # bit1 :info_transaction  # should ignore this one
      # bit1 :non_merchandise
      # bit1 :subtract          # item was subtracted
      # bit1 :cancel            # item was canceled
      # bit1 :negative          # negative item
      # bit1 :upcharge          # negative discount
      # bit1 :additive          # additive discount
      # bit1 :delivery_charges  # (was progressive)

      string :flag_2, :read_length => 1
      #Flag 2 flags
      # bit1 :manual                      # manual discount
      # bit1 :type_percent                     # percentage discount
      # bit1 :cost_plus                   # cost plus item/dept
      # bit1 :fs_payment                  # foodstampable item
      # bit1 :store_promotion             # not used?
      # bit1 :total_transaction_discount  # ticket discount
      # bit1 :plu_transaction_discount    # item discount
      # bit1 :department_transaction_discount

      string :flag_3, :read_length => 1
      #Flag 3 flags
      # bit1 :promotion         # promotion type given
      # bit1 :reduction         # promotion type (reduction given)
      # bit1 :offer             # promotion type (offer given)
      # bit1 :multi_saver
      # bit1 :ext_promotion
      # bit1 :not_net_promotion
      # bit1 :member_discount   # frequent shopper discount
      # bit1 :discount_flag     # item/dept discount allowed flag
      #                         # used in cases of promotions

      uint8 :discount_type    # no idea on field type
      float :percent
      uint8 :return_type      # no idea on field type
      uint8 :tax_pointer_or_discount_item # tax flags of disc item
      uint32 :quantity        # item quantity
      int32 :price           # item price
      int32 :amount          # discount amount

      string :flag_4, :read_length => 1
      # Flag 4 flags
      # bit1 :points_given              # reward points awarded
      # bit1 :customer_account_discount
      # bit1 :ext_trs                   # extended trs
      # bit1 :automatic_discount
      # bit1 :delayed_promotion         # (Lucky) ???
      # bit1 :report_as_tender          # report discount as tender (Lucky) ???
      # bit1 :not_used_optnot_net_fx    # non-netted promotions/freq shopper
      # bit1 :staff_discount            # (ROW) ???

      uint8 :multiple_selling_unit    # Item MSU
      uint16 :tender                  # tender number (Lucky) ???
      uint32 :no_tax_amount           # ???
      float :return_surcharge_percentage

      def upc
        self.item_code.unpack("H*").first
      end

      # roll all flags up into a hex string, hopefully useful
      # as a discount type in the future
      def type_flags
        (flag_1 << flag_2 << flag_3 << flag_4).unpack('H*').first
      end

    end

    class Coupon < BinData::Record
      endian :little

      uint8 :opcode

      # Flag 1
      bit1 :subtract
      bit1 :cancel
      bit1 :suppress_bonus_coupon
      bit1 :ext_coupon_information_transaction
      bit1 :department_net
      bit1 :bonus_coupon_followed
      bit1 :cost_plus
      bit1 :chained_previous_item

      # Flag 2
      bit1 :store_coupon
      bit1 :vendor_coupon
      bit1 :bonus_coupon
      bit1 :upc5_coupon
      bit1 :fs_payment      # foodstamp payment
      bit1 :discount_allowed
      bit1 :manual_entered_amount
      bit1 :manual_entered_department

      int32 :quantity
      int32 :amount
      uint16 :tender_number
      uint8 :tender_type
      uint16 :coupon_dept

      #TODO: write a BCD dynamic primitive type (similar to :uint#)
      string :coupon_code, :read_length => 7
      string :coupon_name, :read_length => 16

      uint8 :tax_pointer
      int16 :minimum_qty
      int16 :plus_amount

      def code
        self.coupon_code.unpack("H*").first
      end

    end

  end
end

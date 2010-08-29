# = Informations
# 
# == License
# 
# Ekylibre - Simple ERP
# Copyright (C) 2009-2010 Brice Texier, Thibaud Mérigon
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see http://www.gnu.org/licenses.
# 
# == Table: accounts
#
#  comment      :text             
#  company_id   :integer          not null
#  created_at   :datetime         not null
#  creator_id   :integer          
#  id           :integer          not null, primary key
#  is_debit     :boolean          not null
#  label        :string(255)      not null
#  last_letter  :string(8)        
#  lock_version :integer          default(0), not null
#  name         :string(208)      not null
#  number       :string(16)       not null
#  updated_at   :datetime         not null
#  updater_id   :integer          
#

class Account < ActiveRecord::Base
  attr_accessor :sum_debit, :sum_credit
  attr_readonly :company_id, :number
  belongs_to :company
  has_many :account_balances
  has_many :balances, :class_name=>AccountBalance.name
  has_many :cashes
  has_many :entry_lines, :class_name=>JournalEntryLine.name
  has_many :journal_entry_lines
  has_many :journals, :class_name=>Journal.name, :foreign_key=>:counterpart_id
  has_many :products
  has_many :purchase_order_lines
  validates_format_of :number, :with=>/^\d(\d(\d[0-9A-Z]*)?)?$/
  validates_uniqueness_of :number, :scope=>:company_id

  # This method allows to create the parent accounts if it is necessary.
  def prepare
    self.label = tc(:label, :number=>self.number.to_s, :name=>self.name.to_s)
  end

  def destroyable?
    self.journal_entry_lines.size <= 0 and self.balances.size <= 0
  end

  def letterable?
    return [:client, :supplier, :attorney].detect do |mode|
      self.number.match(/^#{self.company.preference('accountancy.accounts.third_'+mode.to_s)}/)
    end
  end

  def letterable_entry_lines(started_on, stopped_on)
    self.journal_entry_lines.find(:all, :joins=>"JOIN journal_entries ON (entry_id=journal_entries.id)", :conditions=>["journal_entries.created_on BETWEEN ? AND ? ", started_on, stopped_on], :order=>"letter DESC, journal_entries.number DESC")
  end

  def new_letter
    entry = self.journal_entry_lines.find(:first, :conditions=>["LENGTH(TRIM(letter)) > 0"], :order=>"letter DESC")
    return (entry ? entry.letter.succ : "AAA")
  end

  def letter_entry_lines(journal_entry_lines_id, letter = nil)
    letter ||= self.new_letter
    self.journal_entry_lines.update_all({:letter=>letter}, {:id=>journal_entry_lines_id, :letter=>nil})
  end

  def unletter_entry_lines(letter)
    self.journal_entry_lines.update_all({:letter=>nil}, {:letter=>letter})
    self.update_attribute(:last_letter, self.journal_entry_lines.maximum(:letter))
  end



  def journal_entry_lines_between(started_on, stopped_on)
    self.journal_entry_lines.find(:all, :joins=>"JOIN journal_entries ON (journal_entries.id=entry_id)", :conditions=>["printed_on BETWEEN ? AND ? ", started_on, stopped_on], :order=>"printed_on, journal_entries.id, journal_entry_lines.id")
  end

  def journal_entry_lines_calculate(column, started_on, stopped_on, operation=:sum)
    column = (column == :balance ? "currency_debit - currency_credit" : "currency_#{column}")
    self.journal_entry_lines.calculate(operation, column, :joins=>"JOIN journal_entries ON (journal_entries.id=entry_id)", :conditions=>["printed_on BETWEEN ? AND ? ", started_on, stopped_on])
  end




  # computes the balance for a given financial_year.
  #  def compute(company, financial_year)
  #     debit = self.journal_entry_lines.sum(:debit, :conditions => {:company_id => company}, :joins => "INNER JOIN journal_entries r ON r.id=journal_entry_lines.entry_id AND r.financial_year_id ="+financial_year.to_s).to_f
  #     credit = self.journal_entry_lines.sum(:credit, :conditions => {:company_id => company}, :joins => "INNER JOIN journal_entries r ON r.id=journal_entry_lines.entry_id AND r.financial_year_id ="+financial_year.to_s).to_f
  
  #     balance = {}
  #     unless (debit.zero? and credit.zero?) and not self.number.to_s.match /^12/
  #       balance[:id] = self.id.to_i
  #       balance[:number] = self.number.to_i
  #       balance[:name] = self.name.to_s
  #       balance[:balance] = debit - credit
  #       if debit.zero? or credit.zero?
  #         balance[:debit] = debit
  #         balance[:credit] = credit
  #       end
  #       if not debit.zero? and not credit.zero?
  #         if balance[:balance] > 0  
  #           balance[:debit] = balance[:balance]
  #           balance[:credit] = 0
  #         else
  #           balance[:debit] = 0
  #           balance[:credit] = balance[:balance].abs
  #         end
  #       end
  #     end
  
  #     balance unless balance.empty?
  #   end

  # this method loads the balance for a given period.
  def self.balance(company, from, to, list_accounts=[])
    balance = []
    conditions = "company_id = "+company.to_s
    if not list_accounts.empty?
      conditions += " AND "+list_accounts.collect do |account|
        "number LIKE '"+account.to_s+"%'"
      end.join(" OR ")
    end  
    accounts = Account.find(:all, :conditions => conditions, :order => "number ASC")
    #solde = 0

    res_debit = 0
    res_credit = 0
    res_balance = 0
    
    accounts.each do |account| 
      debit = account.journal_entry_lines.sum(:debit, :conditions =>["CAST(r.created_on AS DATE) BETWEEN ? AND ?", from, to ], :joins => "INNER JOIN journal_entries r ON r.id=journal_entry_lines.entry_id").to_f
      credit = account.journal_entry_lines.sum(:credit, :conditions =>["CAST(r.created_on AS DATE) BETWEEN ? AND ?", from, to ], :joins => "INNER JOIN journal_entries r ON r.id=journal_entry_lines.entry_id").to_f
      
      compute=HashWithIndifferentAccess.new
      compute[:id] = account.id.to_i
      compute[:number] = account.number.to_i
      compute[:name] = account.name.to_s
      compute[:debit] = debit
      compute[:credit] = credit
      compute[:balance] = debit - credit 

      if debit.zero? or credit.zero?
        compute[:debit] = debit
        compute[:credit] = credit
      end
      
      # if not debit.zero? and not credit.zero?
      #         if compute[:balance] > 0  
      #           compute[:debit] = compute[:balance]
      #           compute[:credit] = 0
      #         else
      #           compute[:debit] = 0
      #           compute[:credit] = compute[:balance].abs
      #         end
      #       end
      
      #if account.number.match /^12/
      # raise Exception.new compute[:balance].to_s
      #end
      
      if account.number.match /^(6|7)/
        res_debit += compute[:debit]
        res_credit += compute[:credit]
        res_balance += compute[:balance]
      end

      #solde += compute[:balance] if account.number.match /^(6|7)/
      #      raise Exception.new solde.to_s if account.number.match /^(6|7)/    
      balance << compute
    end
    #raise Exception.new res_balance.to_s
    balance.each do |account| 
      if res_balance > 0
        if account[:number].to_s.match /^12/
          account[:debit] += res_debit
          account[:credit] += res_credit
          account[:balance] += res_balance #solde
        end
      elsif res_balance < 0
        if account[:number].to_s.match /^129/
          account[:debit] += res_debit
          account[:credit] += res_credit
          account[:balance] += res_balance #solde
        end
      end
    end
    # raise Exception.new(balance.inspect)
    balance.compact
  end
  
  # this method loads the general ledger for all the accounts.
  def self.ledger(company, from, to)
    ledger = []
    accounts = Account.find(:all, :conditions => {:company_id => company}, :order=>"number ASC")
    accounts.each do |account|
      compute=[] #HashWithIndifferentAccess.new
      
      journal_entry_lines = account.journal_entry_lines.find(:all, :conditions=>["CAST(r.created_on AS DATE) BETWEEN ? AND ?", from, to ], :joins=>"INNER JOIN journal_entries r ON r.id=journal_entry_lines.entry_id", :order=>"r.number ASC")
      
      if journal_entry_lines.size > 0
        entrys = []
        compute << account.number.to_i
        compute << account.name.to_s
        journal_entry_lines.each do |e|
          entry = HashWithIndifferentAccess.new
          entry[:date] = e.entry.created_on
          entry[:name] = e.name.to_s
          entry[:number_entry] = e.entry.number
          entry[:journal] = e.entry.journal.name.to_s
          entry[:credit] = e.credit
          entry[:debit] = e.debit
          entrys << entry
          # compute[:journal_entry_lines] << entry
        end
        compute << entrys
        ledger << compute
      end
      
    end

    ledger.compact
  end


  # this method loads all the journal_entry_lines having the given letter for the account.
  def balanced_letter?(letter) 
    journal_entry_lines = self.company.journal_journal_entry_lines.find(:all, :conditions => ["letter = ?", letter.to_s], :joins => "INNER JOIN journal_entries r ON r.id = journal_entry_lines.entry_id INNER JOIN financial_years f ON f.id = r.financial_year_id")
    
    if journal_entry_lines.size > 0
      sum_debit = 0
      sum_credit = 0
      journal_entry_lines.each do |entry|
        sum_debit += entry.debit
        sum_credit += entry.credit
      end
      return true if sum_debit == sum_credit
    end
    return false
  end
  
end


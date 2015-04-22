# encoding: utf-8

# This file is shared since oddb2xml 2.0.0 (lib/oddb2xml/parse_compositions.rb)
# with oddb.org src/plugin/parse_compositions.rb
#
# It allows an easy parsing of the column P Zusammensetzung of the swissmedic packages.xlsx file
#

require 'parslet'
require 'parslet/convenience'
include Parslet
VERBOSE_MESSAGES = false

class DoseParser < Parslet::Parser

  # Single character rules
  rule(:lparen)     { str('(') }
  rule(:rparen)     { str(')') }
  rule(:comma)      { str(',') }

  rule(:space)      { match('\s').repeat(1) }
  rule(:space?)     { space.maybe }

  # Things
  rule(:digit) { match('[0-9]') }
  rule(:digits) { digit.repeat(1) }
  rule(:number) {
    (
      str('-').maybe >> (
        str('0') | (match('[1-9]') >> match('[0-9\']').repeat)
      ) >> (
            (str('*') >>  digit.repeat(1)).maybe >>
            match(['.,^']) >> digit.repeat(1)
      ).maybe >> (
        match('[eE]') >> (str('+') | str('-')).maybe >> digit.repeat(1)
      ).maybe
    )
  }
  rule(:radio_isotop) { match['a-zA-Z'].repeat(1) >> lparen >> digits >> str('-') >> match['a-zA-Z'].repeat(1-3) >> rparen >>
                        ((space? >> match['a-zA-Z']).repeat(1)).repeat(0)
                        } # e.g. Xenonum (133-Xe) or yttrii(90-Y) chloridum zum Kalibrierungszeitpunkt
  rule(:ratio_value) { match['0-9:\-\.'].repeat(1)  >> space?}  # eg. ratio: 1:1, ratio: 1:1.5-2.4.
  rule(:identifier) { (match['a-zA-Zéàèèçïöäüâ'] | digit >> str('-'))  >> match['0-9a-zA-Z\-éàèèçïöäüâ\'\/\.'].repeat(0) }
  # handle stuff like acidum 9,11-linolicum specially. it must contain at least one a-z
  rule(:umlaut) { match(['éàèèçïöäüâ']) }
  rule(:identifier_D12) { match['a-zA-Z'] >> digit.repeat(1) }
  rule(:identifier_with_comma) {
    match['0-9,\-'].repeat(0) >> (match['a-zA-Z']|umlaut)  >> (match(['_,']).maybe >> (match['0-9a-zA-Z\-\'\/'] | umlaut)).repeat(0)
  }
  rule(:identifier_without_comma) {
    match['0-9,\-'].repeat(0) >> (match['a-zA-Z']|umlaut)  >> (match(['_']).maybe >> (match['0-9a-zA-Z\-\'\/'] | umlaut)).repeat(0)
  }
  rule(:one_word) { identifier_with_comma }
  rule(:in_parent) { lparen >> one_word.repeat(1) >> rparen }
  rule(:words_nested) { one_word.repeat(1) >> in_parent.maybe >> space? >> one_word.repeat(0) }
  # dose
  rule(:dose_unit)      { (
                           str('g/dm²') |
                           str('% V/V') |
                           str('µg') |
                           str('guttae') |
                           str('mg/ml') |
                           str('MBq') |
                           str('CFU') |
                           str('mg') |
                           str('Mg') |
                           str('kJ') |
                           str('G') |
                           str('g') |
                           str('l') |
                           str('µl') |
                           str('ml') |
                           str('µmol') |
                           str('mmol') |
                           str('U.I.') |
                           str('U.') |
                           str('Mia. U.') |
                           str('%')
                          ).as(:unit) }
  rule(:qty_range)       { (number >> space? >> str('-') >> space? >> number).as(:qty_range) }
  rule(:qty_unit)       { dose_qty >> space? >> dose_unit.maybe }
  rule(:dose_qty)       { number.as(:qty) }
  rule(:dose)           { (str('min.') >> space?).maybe >>
                          ( (qty_range >> space? >> dose_unit.maybe) | (qty_unit | dose_qty |dose_unit)) >> space?
                           }
  rule(:dose_with_unit) { (str('min.') >> space?).maybe >>
                          ( qty_range >> space? >> dose_unit |
                            dose_qty  >> space? >> dose_unit ) >>
                          space?
                        }
  root :dose

end

class SubstanceParser < DoseParser

  rule(:operator)   { match('[+]') >> space? }

  # Grammar parts
  rule(:farbstoff) { (( str('antiox.:').as(:more_info) |
                        str('Überzug:').as(:more_info) |
                        str('arom.:').as(:more_info) |
                        str('color.:').as(:more_info) |
                        str('conserv.:').as(:more_info)
                      ).  >> space).maybe >>
                     (str('E').as(:farbstoff) >>
                      space >> (digits >> match['(a-z)'].repeat(0,3)).as(:digits)
                     ) >>
                      space? >> dose.as(:dose_farbstoff).maybe >> space?

                   } # Match Wirkstoffe like E 270
  rule(:der) { (str('DER:')  >> space >> digit >> match['0-9\.\-:'].repeat).as(:der) >> space?
             } # DER: 1:4 or DER: 3.5:1 or DER: 6-8:1 or DER: 4.0-9.0:1'
  rule(:forbidden_in_substance_name) {
                           str(', corresp.') |
                           str('corresp.') |
                            str('et ') |
                            str('min. ') |
                            str('ut ') |
                            str('ut alia: ') |
                            str('ut alia: ') |
                            str('pro dosi') |
                            str('pro capsula') |
                            (digits.repeat(1) >> space >> str(':')) | # match 50 %
                            str('ad globulos') |
                            str('ana ') |
                            str('ana partes') |
                            str('partes') |
                            str('ad pulverem') |
                            str('ad suspensionem') |
                            str('q.s. ') |
                            str('ad solutionem') |
                            str('ad emulsionem') |
                            str('excipiens')
    }
  rule(:name_without_parenthesis) {
    (
     (str('(') |
      forbidden_in_substance_name).absent? >> (radio_isotop |
                                               str('> 1000') |
                                               str('> 500') |

                                               one_word) >> space?).repeat(1)
  }

  rule(:part_with_parenthesis) { lparen >> ( (lparen | rparen).absent? >> any).repeat(1) >>
                                 (part_with_parenthesis | rparen >> str('-like:') | rparen  ) >> space?
                               }
  rule(:name_with_parenthesis) {
    forbidden_in_substance_name.absent? >>
    ((str(',') | lparen).absent? >> any).repeat(0) >> part_with_parenthesis >>
    (forbidden_in_substance_name.absent? >> (one_word | part_with_parenthesis | rparen) >> space?).repeat(0)
  }
  rule(:substance_name) { (der | farbstoff | name_with_parenthesis | name_without_parenthesis) >> str('.').maybe >> str('pro dosi').maybe }
  rule(:simple_substance) { substance_name.as(:substance_name) >> space? >> dose.as(:dose).maybe >> space? >> ratio.maybe}

  rule(:pro_dose) { str('pro') >>  space >> dose.as(:dose_corresp) }

  rule(:substance_corresp) {
                    simple_substance >> space? >> ( str('corresp.') | str(', corresp.')) >> space >> simple_substance.as(:substance_corresp)
    }

    # TODO: what does ut alia: impl?
  rule(:substance_ut) {
    (substance_lead.maybe >> simple_substance).as(:substance_ut) >>
  (space? >> str('ut ')  >>
    space? >> str('alia:').absent? >>
    (excipiens |
    substance_name >> space? >> str('corresp.') >> space >> simple_substance |
    simple_substance
    ).as(:for_ut)
  ).repeat(1) >>
    space? # >> str('alia:').maybe >> space?
  }

  rule(:substance_more_info) { # e.g. "acari allergeni extractum 5000 U.:
      (str('ratio:').absent? >> (identifier|digits) >> space?).repeat(1).as(:more_info) >> space? >> (str('U.:') | str(':')) >> space?
    }

  rule(:dose_pro) { (
                       str('excipiens ad solutionem pro ') |
                       str('aqua q.s. ad gelatume pro ') |
                       str('aqua q.s. ad solutionem pro ') |
                       str('aqua q.s. ad suspensionem pro ') |
                       str('q.s. ad pulverem pro ') |
                       str('excipiens ad emulsionem pro ') |
                       str('excipiens ad pulverem pro ') |
                       str('aqua ad iniectabilia q.s. ad solutionem pro ')
                    )  >> dose.as(:dose_pro) >> space? >> ratio.maybe
  }

  rule(:excipiens)  { (dose_pro |
                       str('excipiens') |
                       str('ad pulverem') |
                       str('pro charta') |
                       str('aqua ad iniectabilia q.s. ad solutionem') |
                       str('ad solutionem') |
                       str('q.s. ad') |
                       str('aqua q.s. ad') |
                       str('saccharum ad') |
                       str('aether q.s.') |
                       str('aqua ad iniectabilia') |
                       str('ana partes')
                      ) >> space? >>
                      ( any.repeat(0) )
                      }

  rule(:substance_lead) {
                      str('residui:').as(:residui) >> space? |
                      str('mineralia').as(:mineralia) >> str(':') >> space? |
                      str('Solvens:').as(:solvens) >> space? |
                      substance_more_info
    }
  rule(:corresp_substance) {
                            (str(', corresp.') | str('corresp.')) >> space? >>
                            (
                             simple_substance.as(:substance_corresp) |
                             dose.as(:dose_corresp_2)
                            )
  }

  rule(:ratio) { str('ratio:') >>  space >> ratio_value }

  rule(:solvens) { (str('Solvens:') | str('Solvens (i.m.):'))>> space >> (any.repeat).as(:solvens) >> space? >>
                   (substance.as(:substance) >> str('/L').maybe).maybe  >>
                    any.maybe
                }
  rule(:substance_with_digits_at_end_and_dose) {
    ((one_word >> space?).repeat(1) >> match['0-9\-'].repeat(1)).as(:substance_name) >>
    space? >> dose.as(:dose).maybe
  }

  rule(:substance) {
    ratio.as(:ratio) |
    solvens |
    der  >> corresp_substance.maybe |
    excipiens.as(:excipiens) |
    farbstoff |
    substance_ut |
    substance_more_info.maybe >> simple_substance >> corresp_substance.maybe >> space? >> dose_pro.maybe >> str('pro dosi').maybe
    # TODO: Fix this problem
    # substance_with_digits_at_end_and_dose for unknown reasons adding this as last alternative disables parsing for simple stuff like 'glyceroli monostearas 40-55'
  }

  rule(:histamin) { str('U = Histamin Equivalent Prick').as(:histamin) }
  rule(:praeparatio){ ((one_word >> space?).repeat(1).as(:description) >> str(':') >> space?).maybe >>
                      (name_with_parenthesis | name_without_parenthesis).repeat(1).as(:substance_name) >>
                      number.as(:qty) >> space >> str('U.:') >> space? >>
                      ((identifier >> space?).repeat(1).as(:more_info) >> space?).maybe
                    }

  rule(:substance_separator) { (comma | str('et ') | str('ut alia: ')) >> space? }
  rule(:one_substance)       { (substance).as(:substance) }
  rule(:one_substance)       { (praeparatio | histamin | substance).as(:substance) }
  rule(:all_substances)      { (one_substance >> substance_separator.maybe).repeat(1) }
  root :all_substances
end

class CompositionParser < SubstanceParser

  rule(:composition) { all_substances }
  rule(:label_id) {
     (
                           str('V') |
                           str('IV') |
                           str('III') |
                           str('II') |
                           str('I') |
                           str('A') |
                           str('B') |
                           str('C') |
                           str('D') |
                           str('E')
     )
  }
  rule(:label_separator) {  (str('):')  | str(')')) }
  rule(:label) { label_id.as(:label) >> space? >>
    label_separator >> str(',').absent?  >>
               (space? >> (match(/[^:]/).repeat(0)).as(:label_description)  >> str(':') >> space).maybe
  }
  rule(:leading_label) {    label_id >> label_separator >> (str(' et ') | str(', ') | str(' pro usu: ') | space) >>
                            label_id >> label_separator >> any.repeat(1)  |
                            label
    }
  rule(:expression_comp) {  leading_label.maybe >> space? >> composition.as(:composition) }
  root :expression_comp
end


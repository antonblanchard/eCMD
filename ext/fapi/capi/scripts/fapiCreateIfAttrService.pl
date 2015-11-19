#!/usr/bin/perl
# $Id$
# Purpose:  This perl script will parse HWP Attribute XML files and
# initfile attr files and create the fapiGetInitFileAttr() function
# in a file called fapiAttributeService.C
#
# Author: Mike Jones
#
# Change Log **********************************************************
#
#  Flag  Track#    Userid    Date      Description
#  ----  --------  --------  --------  -----------
#                  mjjones   11/15/11  Copied from fapiParseAttributeInfo
#                  mjjones   12/12/11  Support all attributes if no if-attr
#                                      files specified (for Cronus)
#                  mjjones   01/13/12  Use new ReturnCode interfaces
#                  mjjones   02/08/12  Handle attribute files with 1 entry
#                  mjjones   06/12/12  Handle privileged attributes
#                  mjjones   09/28/12  Minor change to add FFDC on error
#                  mjjones   10/26/12  Output attrId/targType on error
#
# End Change Log ******************************************************

use strict;

#------------------------------------------------------------------------------
# Print Command Line Help
#------------------------------------------------------------------------------
my $numArgs = $#ARGV + 1;
if ($numArgs < 3)
{
    print ("Usage: fapiCreateIfAttrService.pl <output dir>\n");
    print ("           [<if-attr-file1> <if-attr-file2> ...]\n");
    print ("           -a <attr-xml-file1> [<attr-xml-file2> ...]\n");
    print ("  This perl script will parse if-attr files (containing the\n");
    print ("  attributes used by the initfile) and attribute XML files\n");
    print ("  (containing all HWPF attributes) and create the\n");
    print ("  fapiGetInitFileAttr() function in a file called\n");
    print ("  fapiAttributeService.C. Only the attributes specified in\n");
    print ("  the if-attr files are supported. If no if-attr files are\n");
    print ("  specified then all attributes are supported\n");
    exit(1);
}

#------------------------------------------------------------------------------
# Specify perl modules to use
#------------------------------------------------------------------------------
use XML::Simple;
my $xml = new XML::Simple (KeyAttr=>[]);

# Uncomment to enable debug output
#use Data::Dumper;

#------------------------------------------------------------------------------
# Open output file for writing
#------------------------------------------------------------------------------
my $asFile = $ARGV[0];
$asFile .= "/";
$asFile .= "fapiAttributeService.C";
open(ASFILE, ">", $asFile);

#------------------------------------------------------------------------------
# Print Start of file information to fapiAttributeService.C
#------------------------------------------------------------------------------
print ASFILE "// fapiAttributeService.C\n";
print ASFILE "// This file is generated by perl script fapiCreateIfAttrService.pl\n\n";
print ASFILE "#include <fapiAttributeService.H>\n";
print ASFILE "#include <fapiChipEcFeature.H>\n";
print ASFILE "#include <fapiPlatTrace.H>\n\n";
print ASFILE "namespace fapi\n";
print ASFILE "{\n\n";
print ASFILE "ReturnCode fapiGetInitFileAttr(const AttributeId i_id,\n";
print ASFILE "                               const Target * i_pTarget,\n";
print ASFILE "                               uint64_t & o_val,\n";
print ASFILE "                               const uint32_t i_arrayIndex1,\n";
print ASFILE "                               const uint32_t i_arrayIndex2,\n";
print ASFILE "                               const uint32_t i_arrayIndex3,\n";
print ASFILE "                               const uint32_t i_arrayIndex4)\n";
print ASFILE "{\n";
print ASFILE "    ReturnCode l_rc;\n\n";

my $xmlFiles = 0;
my $attCount = 0;
my $numIfAttrFiles = 0;
my @attrIds;

#------------------------------------------------------------------------------
# Element names
#------------------------------------------------------------------------------
my $attribute = 'attribute';

#------------------------------------------------------------------------------
# For each argument
#------------------------------------------------------------------------------
foreach my $argnum (1 .. $#ARGV)
{
    my $infile = $ARGV[$argnum];

    if ($infile eq '-a')
    {
        # Start of attribute XML files
        $xmlFiles = 1;
        next;
    }

    if ($xmlFiles == 0)
    {
        #----------------------------------------------------------------------
        # Process initfile attr file. This file contains the HWPF attributes
        # that the initfile uses.
        #----------------------------------------------------------------------
        $numIfAttrFiles++;
        open(ATTRFILE, "<", $infile);
        
        # Read each line of the file (each line contains an attribute)
        while(my $fileAttrId = <ATTRFILE>)
        {
            # Remove newline
            chomp($fileAttrId);

            # Store the attribute in @attrIds if it does not already exist
            my $match = 0;

            foreach my $attrId (@attrIds)
            {
                if ($fileAttrId eq $attrId)
                {
                    $match = 1;
                    last;
                }
            }

            if (!($match))
            {
                push(@attrIds, $fileAttrId);
            }
        } 

        close(ATTRFILE);
    }
    else
    {
        #----------------------------------------------------------------------
        # Process XML file. The ForceArray option ensures that there is an
        # array of attributes even if there is only one attribute in the file
        #----------------------------------------------------------------------
        my $attributes = $xml->XMLin($infile, ForceArray => [$attribute]);

        #----------------------------------------------------------------------
        # For each Attribute
        #----------------------------------------------------------------------
        foreach my $attr (@{$attributes->{attribute}})
        {
            #------------------------------------------------------------------
            # Check that the AttributeId exists
            #------------------------------------------------------------------
            if (! exists $attr->{id})
            {
                print ("fapiParseAttributeInfo.pl ERROR. Att 'id' missing\n");
                exit(1);
            }

            #------------------------------------------------------------------
            # Find if the attribute is used by any initfile. If no if-attr
            # files were specified then support all attributes
            #------------------------------------------------------------------
            my $match = 0;

            if ($numIfAttrFiles)
            {
                foreach my $attrId (@attrIds)
                {
                    if ($attr->{id} eq $attrId)
                    {
                        $match = 1;
                        last;
                    }
                }
            }
            else
            {
                $match = 1;
            }

            if (!($match))
            {
                # Look at the next attribute in the XML file
                next;
            }

            #------------------------------------------------------------------
            # Figure out the number of attribute array dimensions
            #------------------------------------------------------------------
            my $numArrayDimensions = 0;
            if ($attr->{array})
            {
                # Remove leading whitespace
                my $dimText = $attr->{array};
                $dimText =~ s/^\s+//;

                # Split on commas or whitespace
                my @vals = split(/\s*,\s*|\s+/, $dimText);

                $numArrayDimensions=@vals;
            }

            #------------------------------------------------------------------
            # Print the attribute get code to fapiAttributeService.C
            #------------------------------------------------------------------
            if ($attCount > 0)
            {
                print ASFILE "    else ";
            }
            else
            {
                print ASFILE "    ";
            }
            $attCount++;

            print ASFILE "if (i_id == $attr->{id})\n";
            print ASFILE "    {\n"; 
            print ASFILE "        $attr->{id}_Type l_attr;\n";

            if (exists $attr->{privileged})
            {
                print ASFILE "        l_rc = FAPI_ATTR_GET_PRIVILEGED($attr->{id}, i_pTarget, l_attr);\n";
            }
            else
            {
                print ASFILE "        l_rc = FAPI_ATTR_GET($attr->{id}, i_pTarget, l_attr);\n";
            }
            print ASFILE "        o_val = l_attr";

            if ($numArrayDimensions >= 5)
            {
                print ("fapiParseAttributeInfo.pl ERROR. More than 4 array dimensions!!\n");
                exit(1);
            }
            else
            {
                for (my $i = 0; $i < $numArrayDimensions; $i++)
                {
                    print ASFILE "[i_arrayIndex";
                    print ASFILE $i+1;
                    print ASFILE "]";
                }
            }

            print ASFILE ";\n";
            print ASFILE "    }\n";
        }
    }
}

#------------------------------------------------------------------------------
# Print End of file information to fapiAttributeService.C
#--------------------------------------------------------------------------
if ($attCount > 0)
{
    print ASFILE "    else\n";
}
print ASFILE "    {\n";
print ASFILE "        FAPI_ERR(\"fapiGetInitFileAttr: Unrecognized attr ID: 0x%x\", i_id);\n";
print ASFILE "        l_rc.setFapiError(FAPI_RC_INVALID_ATTR_GET);\n";
print ASFILE "        l_rc.addEIFfdc(0, &i_id, sizeof(i_id));\n";
print ASFILE "    }\n\n";
print ASFILE "    if (l_rc)\n";
print ASFILE "    {\n";
print ASFILE "        if (i_pTarget)\n";
print ASFILE "        {\n";
print ASFILE "            FAPI_ERR(\"fapiGetInitFileAttr: Error getting attr ID 0x%x from targType 0x%x\",\n";
print ASFILE "                     i_id, i_pTarget->getType());\n";
print ASFILE "        }\n";
print ASFILE "        else\n";
print ASFILE "        {\n";
print ASFILE "            FAPI_ERR(\"fapiGetInitFileAttr: Error getting attr ID 0x%x from system target\",\n";
print ASFILE "                     i_id);\n";
print ASFILE "        }\n";
print ASFILE "    }\n\n";
print ASFILE "    return l_rc;\n";
print ASFILE "}\n\n";
print ASFILE "}\n";


#------------------------------------------------------------------------------
# Close output file
#------------------------------------------------------------------------------
close(ASFILE);

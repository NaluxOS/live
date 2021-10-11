import sys
import re

infile = open(sys.argv[1], "r")
package_to_search = sys.argv[2]
field_to_search = sys.argv[3]

found_package = False

for line in infile:
    # Necessary because another newline is added after every line
    # And packages are seperated by empty lines
    line = line.rstrip()

    # The package section usually begins with "Package: "
    # So we search for it here
    if re.search(r"^Package: " + re.escape(package_to_search) + r"$", line):
            found_package = True

            # Go through all fields of the package until an empty line comes
            # Packages are seperated by empty lines
            while not re.search(r"^$", line):
                if re.search(r"^" + re.escape(field_to_search) + r":", line):
                    field_value = line.replace(field_to_search + ": ", "", 1)
                    print(field_value)
                    exit(0)

                line = next(infile).rstrip()

# Differenciate between package not found and field from package not found (but package found)
# Because many fields are optional and dont have to be present
if found_package == True:
    # Field not found
    exit(2)
else:
    # Package not found
    exit(1)
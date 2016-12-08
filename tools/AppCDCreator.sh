#!/bin/bash -e

APP_CREATOR_LOG="/tmp/AppCreatorScript.$(date '+%Y%m%d%H%M%S').log"
exec 2>"$APP_CREATOR_LOG"
set -x

ISO_VERSION="${1:-$(date '+FW%W.%w')}"
ISO_OHR_ID="${2:-null}"
ISO_DEST_FILENAME="/InstallCDData/ISOOutputDir/APPCD-EverestII-V1##XR642_${ISO_VERSION}.iso"
INSTALL_MANAGER_FOLDER=/InstallCDData/InstallManager
EVEREST2_RPMS_LOCATION=/InstallCDData/Programs/EverestII/GDXE/RPMS
# ISO_TMP_FOLDER="/tmp/ISOInputDir"
ISO_TMP_FOLDER="$(mktemp -d /tmp/ISOInputDir.XXXXXX)"
ENCRYPTOR_FOLDER="$(mktemp -d /tmp/ISOInputDir-Encryptor.XXXXXX)"
MASTER_XML="$(mktemp /tmp/master.xml.XXXXXX)"
INSTALL_CD_CONFIG_XML=/usr/local/apache-tomcat-5.5.27/webapps/ROOT/InstallCDConfig.xml

CP=/bin/cp
JAVAC=/usr/java/default/bin/javac
JAVA=/usr/java/default/bin/java

# echo "ISO image folder: $ISO_TMP_FOLDER"

export CLASSPATH=/usr/local/apache-tomcat-5.5.27/webapps/ROOT:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/AppCDCreator.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/XmlSchema-1.0.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/xfire-all-1.0.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/xercesImpl.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/xbean-spring-2.2.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/xbean-2.1.0.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/wstx-asl-2.9.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/wsdl4j-1.5.2.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/stax-api-1.0.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/spring-1.2.6.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/servlet-api-2.3.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/rda.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/log4j-1.2.6.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/jdom-1.0.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/jaxen-1.1-beta-8.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/decrypt.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/commons-logging-1.0.4.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/commons-httpclient-3.0.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/commons-codec-1.3.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/commandexecutor.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/AppCDWebService.jar:/usr/local/apache-tomcat-5.5.27/webapps/ROOT/lib/mail-1.3.3_01.jar

# /usr/java/default/bin/java -DipAddress=127.0.0.1 -classpath "$CLASSPATH" appcdcreator.AppCDJFrame

RPM_INSTALL_ORDER="$(/bin/cat "$INSTALL_CD_CONFIG_XML" | /bin/fgrep DefaultInstallOrder | /bin/grep -Eo '"[^"]+"' | /bin/sed 's/"//g')"
RPM_INSTALL_LIST="$(echo "$RPM_INSTALL_ORDER" | /bin/sed "s/,/\n/g")"

mkdir -p "${ISO_TMP_FOLDER}/GDXE/RPMS/"

/bin/cat > "${ISO_TMP_FOLDER}/AppsCDDesc.txt" <<EOF
Version: EverestII ${ISO_VERSION}
Created By: Nobody
Created On: Mars
Packages:
Comment:
EOF

pushd "$EVEREST2_RPMS_LOCATION" >/dev/null
/bin/cat > "$MASTER_XML" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!-- Create time: $(date '+%F %T') -->
<XRaySWCD>
  <Version> ${ISO_VERSION} </Version>
  <PartNo> ${ISO_OHR_ID} </PartNo>
  <Type> APPCD </Type>
  <CDName> EverestII </CDName>
  <RPMS>
EOF
RPMS_LIST="$(/bin/ls -1)"
RPMS_LIST_TOTAL="$(echo "$RPM_INSTALL_LIST" | wc -l | /usr/bin/awk '{print $1}')"
RPMS_INDEX=0
echo "$RPM_INSTALL_LIST" | while read ONE_RPM; do
    RPMS_INDEX="$(($RPMS_INDEX + 1))"
    echo "$RPMS_LIST" | /bin/grep -Ei "^$ONE_RPM" | while read RPMFILE; do
        "$CP" -f "${EVEREST2_RPMS_LOCATION}/$RPMFILE" "${ISO_TMP_FOLDER}/GDXE/RPMS/"
        /bin/cat >> "$MASTER_XML" <<EOF
    <RPM>
      <Name>${RPMFILE}</Name>
      <flags>
        <flag> force </flag>
        <flag> nodeps </flag>
      </flags>
    </RPM>
EOF
    done
    RPMS_LIST="$(echo "$RPMS_LIST" | /bin/grep -Eiv "^$ONE_RPM")"
    echo -n " $(( $RPMS_INDEX * 100 / $RPMS_LIST_TOTAL ))%   "$'\r'
done
echo ""
/bin/cat >> "$MASTER_XML" <<EOF
  </RPMS>
</XRaySWCD>
EOF
popd > /dev/null

pushd "$INSTALL_MANAGER_FOLDER" >/dev/null
for FILE in *; do
    if [ "$FILE" == "EXCLUDED" ]; then
        "$CP" -r "$FILE" "${ISO_TMP_FOLDER}/GDXE/RPMS/"
    else
        "$CP" -r "$FILE" "${ISO_TMP_FOLDER}/"
    fi
done
popd > /dev/null

echo "<!-- Start of master.xml -->" >&2
/bin/cat "$MASTER_XML" >&2
echo "<!-- End of master.xml -->" >&2

pushd "$ENCRYPTOR_FOLDER" > /dev/null
/bin/cat > EncryptMaster.java <<EOF
import appcdwebservice.*;

import java.io.*;

import java.io.FileWriter;

import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import javax.crypto.BadPaddingException;
import javax.crypto.Cipher;
import javax.crypto.IllegalBlockSizeException;
import javax.crypto.KeyGenerator;
import javax.crypto.NoSuchPaddingException;
import javax.crypto.SecretKey;

import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;

public class EncryptMaster {
    public static void main(String[] args) throws Exception {
        String xmlOuput= ""
$(/bin/cat "$MASTER_XML" | /bin/sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/^/            + "/' -e 's/$/\\n"/');

        try {
            Encryptor encryptor = new Encryptor();
            byte[] encBytes = encryptor.encrypt(xmlOuput);

            Serializer.serialize("${ISO_TMP_FOLDER}/master.xml", encBytes);
            String encKeyPath = "${ISO_TMP_FOLDER}/Key.txt";
            Serializer.serialize(encKeyPath, encryptor.getKey());
        } catch (Exception ex) {
            ex.printStackTrace();
        }
    }
}
class Encryptor {

    private Cipher cipher;
    //private BASE64Encoder encoder = new BASE64Encoder();

    private SecretKey secretKey;

    /** Creates a new instance of Encryptor */
    public Encryptor() {
        try {
            KeyGenerator keyGen = KeyGenerator.getInstance("AES");
            keyGen.init(128);
            secretKey = keyGen.generateKey();
            cipher = Cipher.getInstance("AES");
            cipher.init(Cipher.ENCRYPT_MODE, secretKey);
        }
        catch (NoSuchAlgorithmException ex) {
            ex.printStackTrace();
        }
        catch (NoSuchPaddingException ex) {
                ex.printStackTrace();
        }
        catch (InvalidKeyException ex) {
                ex.printStackTrace();
        }
    }

    public byte[] encrypt(String input) {
        String encryptedStr = null;
        byte[] resultBytes = null;
        byte[] srcBytes = input.getBytes();
        try {
            resultBytes = cipher.doFinal(srcBytes);
            //encryptedStr = encoder.encode(resultBytes);
        }
        catch (IllegalBlockSizeException ex) {
            ex.printStackTrace();
        }
        catch (BadPaddingException ex) {
            ex.printStackTrace();
        }
        return resultBytes;
    }

    public SecretKey getKey() {
        return secretKey;
    }
}
class Serializer {

    /** Creates a new instance of Serializer */
    public Serializer() {
    }

    public static void serialize(String filename, Object obj) {
        System.out.println(obj);
        FileOutputStream fstream;
        try {
            fstream = new FileOutputStream(filename);
            ObjectOutputStream stream = new ObjectOutputStream(fstream);
            stream.writeObject(obj);
        } catch (IOException ex) {
            ex.printStackTrace();
        }
    }

    public static Object deserialize(String filename) {
        Object obj = null;
        FileInputStream fstream;
        try {
            fstream = new FileInputStream(filename);
            ObjectInputStream stream = new ObjectInputStream(fstream);
            obj = stream.readObject();
        } catch (IOException ex) {
            ex.printStackTrace();
        }
         catch (ClassNotFoundException ex) {
                ex.printStackTrace();
            }
        System.out.println(obj);
        return obj;
    }

}

EOF

echo "// EncryptMaster.java" >&2
/bin/cat EncryptMaster.java >&2
echo "// End of EncryptMaster.java" >&2

"$JAVAC" -classpath "$CLASSPATH" EncryptMaster.java
"$JAVA" -classpath ".:$CLASSPATH" EncryptMaster
popd > /dev/null

/usr/bin/mkisofs -R -J -l -D -input-charset UTF-8 -o "${ISO_DEST_FILENAME}" "${ISO_TMP_FOLDER}"
echo "${ISO_DEST_FILENAME}"
ls -l "${ISO_DEST_FILENAME}"
rm -r "$ISO_TMP_FOLDER" "$ENCRYPTOR_FOLDER" "$MASTER_XML"
echo ""
echo "Log: $APP_CREATOR_LOG"
echo ""
echo "Oh yeah, I did it, kick my ass please...."
echo ""


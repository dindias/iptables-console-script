#!/bin/bash
iptables=/sbin/iptables

# Función para comprobar si la IP es válida
function validar_ip {
    local  ip=$1
    local  stat=1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

while true; do
    echo -e "Introduce IP Inicial"
    read IP
    validar_ip $IP
    if [ $? -eq 0 ]; then
        break
    else
        echo "La IP introducida no es válida. Introduce una IP válida."
    fi
done

echo -e "Introduce Puerto Inicial"
read PORT
echo -e "Introduce puertos destino a configurar (separados por comas)"
read PORTS
echo -e "Introduce cantidad de reglas a configurar"
read RULES

# Convierte la cadena de puertos en un array
IFS=',' read -ra PORTS_ARRAY <<< "$PORTS"

for ((i = 0; i < RULES; i++)); do
  # Verifica si existen reglas para la IP especificada
  RULES_EXIST=$(sudo -S iptables -t nat -nvxL --line-numbers | grep $IP | wc -l)
  if [ "$RULES_EXIST" -gt 0 ]; then
    echo "Reglas existentes para IP $IP:"
    sudo -S iptables -t nat -nvxL --line-numbers | grep $IP
    read -p "¿Desea eliminar las reglas existentes para la IP $IP? [y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      # Pregunta si se desean eliminar reglas específicas
      read -p "¿Desea eliminar reglas específicas? [y/n] " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Pide los números de las reglas a eliminar
        read -p "Introduzca los números de línea de las reglas que desea eliminar (separados por comas): " -r RULES_TO_DELETE
        echo
        IFS=',' read -ra RULES_TO_DELETE_ARRAY <<< "$RULES_TO_DELETE"

        # Sorts the rule numbers in descending order
        IFS=$'\n' RULES_TO_DELETE_ARRAY=($(sort -rn <<<"${RULES_TO_DELETE_ARRAY[*]}"))
        unset IFS

        # Print the rules to be deleted and ask for confirmation
        for RULE in "${RULES_TO_DELETE_ARRAY[@]}"; do
          echo "Regla a eliminar: $(sudo iptables -t nat -L PREROUTING $RULE)"
        done

        read -p "¿Estás seguro de que quieres eliminar estas reglas? [Y/n] " -r CONFIRM
        if [[ $CONFIRM =~ ^[Yy]$ ]]
        then
          # Deletes the specified rules starting from the highest number
          for RULE in "${RULES_TO_DELETE_ARRAY[@]}"; do
            sudo -S iptables -t nat -D PREROUTING "$RULE"
            echo "Regla eliminada: $RULE";
          done
        else
          echo "Se ha cancelado la eliminación de las reglas."
        fi
      else
        # Elimina todas las reglas existentes para la IP
        RULES_TO_DELETE=()

        sudo -S iptables -t nat -nvxL --line-numbers | grep "$IP" |
          awk '{print $1 " " $12 " " $13 " " $14}' | sort -nr | while read -r line pub_port ip; do 
            RULES_TO_DELETE+=("$line")
            echo "Regla a eliminar. No. de línea: $line, Puerto: $pub_port, IP: $ip"
        done

        read -p "¿Estás seguro de que quieres eliminar estas reglas? [Y/n] " -r CONFIRM
        if [[ $CONFIRM =~ ^[Yy]$ ]]
        then
          for RULE in "${RULES_TO_DELETE[@]}"; do
            sudo iptables -t nat -D PREROUTING "$RULE"
            echo "Regla eliminada: $RULE"
          done
          echo "Todas las reglas existentes eliminadas para IP $IP"
        else
          echo "Se ha cancelado la eliminación de las reglas."
        fi
      fi
    fi
  fi
  for PORTS in "${PORTS_ARRAY[@]}"; do
    echo "Configurando reglas para $PORT -> $IP:$PORTS"
    sudo $iptables -t nat -A PREROUTING -p tcp --dport $PORT -j DNAT --to-destination $IP:$PORTS
    ((PORT++))
  done
  # Incrementa el cuarto octeto de la IP
  OCTETO=$(echo $IP | awk -F. '{print $4}')
  if [ $OCTETO -eq 0 ]; then
      IP=$(echo $IP | awk -F. '{print $1"."$2"."$3".1"}')
  elif [ $OCTETO -eq 254 ]; then
      IP=$(echo $IP | awk -F. '{print $1"."$2"."$3+1".1"}')
  else
      IP=$(echo $IP | awk -F. '{print $1"."$2"."$3"."$4+1}')
  fi
  echo
done

sudo bash -c 'iptables-save > /etc/iptables/rules.v4'
echo "Reglas guardadas correctamente"

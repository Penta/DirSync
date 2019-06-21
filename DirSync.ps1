
 ##################### Script de synchronisation de deux dossiers. ##################
 #                                                                                  #
 # Aucun des deux dossiers n'est le principal, les modifications peuvent se faire   #
 # dans les deux dossiers indépendement. Le fichier le plus récent sera alors copié #
 # dans l'autre dossier.                                                            #
 #                                                                                  #
 # La suppression synchronisée peut être désactivée plus bas.                       #
 #                                                                                  #
 # Il est judicieux de créer une tâche dans le planificateur des tâches pour        #
 # exécuter ce script de façon automatique (toutes les 15 minutes par exemple).     #
 #                                                                                  #
 #                                                                                  #
 #           Version : 1.0.3                      Auteur : Andy Esnard              #
 #                                                                                  #
 ####################################################################################


 
                               #######################
                              # Variables modifiables #
######################################################################################

####### Dossiers à synchroniser
$Dir1 = "\\127.0.0.1\C$\test1"
$Dir2 = "\\127.0.0.1\C$\test2"

####### Fichiers annexes utilisés par le script
$FichierLog = "C:\DirSync.log" 
$historiqueCSV = "C:\Historique.csv" # Utilisé pour reperérer la suppression d'un fichier et non la création

####### Variable pour activer la suppression de fichiers ($false = Les fichiers ne seront jamais supprimés par le script, ils seront restaurés si ils ont été supprimés sur un des deux noeuds)
$synchroSuppression = $true

####### Vérifie le hash des dossiers avant de s'executer, peut faire perdre en performance. ($true = activé)
$checkHash=$false

####### Désactive les logs d'informations dans le fichier de log (Pour diminuer la taille du log et n'avoir que les erreurs/warnings)
$noInfo=$false

####### Renvoie un code d'erreur si il y a une erreur, peut être pratique pour renvoyer l'erreur au task scheduler, mais fait planter l'invite de commande Powershell ou l'ISE pour une exécution manuelle
$retourErreur=$true

######################################################################################



# Fonction pour afficher et logger des messages
function Logger {
    param ($texte, $niveau)

    $couleur = "White"

    if (!($niveau -lt 0))
    {
        # On assigne le type d'erreur et la couleur du message correspondant au niveau du message
        if ($niveau -eq 0) {
            $texte = "[INFO] " + $texte
            $couleur = "White"
        }
        elseif ($niveau -eq 1) {
            $texte = "[WARNING] " + $texte
            $couleur = "Yellow"
        }
        elseif ($niveau -eq 2) {
            $texte = "[ERROR] " + $texte
            $couleur = "Red"
        }
        else {
            $texte = "[UNKNOWN] " + $texte
            $couleur = "Blue"
        }

        # On récupère la date du log
        $LogDate = $("[" + $(Get-Date -UFormat "%D %H:%M:%S") + "] ")
        $texteFinal = $LogDate + $texte

        # On affiche le message dans l'invite de commande
        Write-Host $LogDate -NoNewline
        Write-Host $texte -ForegroundColor $couleur

        if (!($couleur -eq "White" -And $noInfo)) { # Si les logs pour les info ne sont pas désactivés
            # On écrit le message dans le fichier de log
            try {
	            if (!($texteFinal -eq "")) { $texteFinal.ToString() >> $FichierLog }
	        }
            catch {
		        Write-Host "$($LogDate)[ERROR] Erreur durant l'écriture sur le fichier de log '$($FichierLog)': $($_.Exception.Message)" -ForegroundColor "Red"
	        }
        }
    }
    elseif ($niveau -eq -1) {
        $texteFinal = $texte

        # On écrit le message dans le fichier de log
        try {
	        if (!($texteFinal -eq "")) { $texteFinal.ToString() >> $FichierLog }
	    }
        catch {
		    Write-Host "$($LogDate)[ERROR] Erreur durant l'écriture sur le fichier de log '$($FichierLog)': $($_.Exception.Message)" -ForegroundColor "Red"
	    }
    }
    else {
        Write-Host $texte
    }
}

# Fonction permettant d'arrêter le script (et de renvoyer un code d'erreur si activé)
function ArretErreur {
    param ($codeErreur)

    if ($codeErreur) { [Environment]::Exit(1) }
    else { Exit }
}

# Fonction trouvée sur Internet pour calculer le hash d'un dossier
function Get-FolderHash ($folder) {
    dir $folder -Recurse | ?{!$_.psiscontainer} | %{[Byte[]]$contents += [System.IO.File]::ReadAllBytes($_.fullname)}
    $hasher = [System.Security.Cryptography.SHA1]::Create()
    [string]::Join("",$($hasher.ComputeHash($contents) | %{"{0:x2}" -f $_}))
}

# Fonction principale du script, elle synchronise un dossier vers un autre
function SynchroDossier {
    param ($source, $destination, $historiqueDossier)

    cd $source

    # Pour chaque fichier dans le dossier (et dans les sous-dossiers)
    Get-ChildItem $source -Recurse | Foreach-Object {
        $fichier =  $_.FullName
        $fichierRelatif = (Resolve-Path $fichier -Relative).Substring(2)
        $fichierDest = $destination + "\" + $fichierRelatif

        # Si c'est un dossier
        if ((Get-Item $fichier) -is [System.IO.DirectoryInfo]) {
            if (!(Test-Path $fichierDest)) { # Si le dossier n'existe pas sur le dossier de destination
                if (!($historiqueDossier.Contains($fichierRelatif)) -Or !$synchroSuppression) { # Si le dossier n'est pas dans l'historique (ou que la suppression est désactivée)
                    Logger "Création du dossier '$($fichierRelatif)' sur '$($destination)'..." 0
                    try { (MkDir $fichierDest -ErrorAction 'SilentlyContinue') | Out-Null } # On créé le dossier
                    catch { Logger "Une erreur est survenue durant la création du dossier '$($fichierRelatif)' sur '$($destination)': $($_.Exception.Message)" 1 }
                }
                else { # Si le dossier existait avant (et que la suppression est activée)
                    Logger "Suppression du dossier '$($fichierRelatif)' sur '$($source)'..." 0
                    try { (Del $fichier -Recurse -ErrorAction 'SilentlyContinue') | Out-Null } # On le supprime
                    catch { Logger "Une erreur est survenue durant la suppression du dossier '$($fichierRelatif)' sur '$($destination)': $($_.Exception.Message)" 1 }
                }
            }
        }
        else { # Si c'est un fichier
            if (!(Test-Path $fichierDest)) { #Si le fichier n'existe pas dans le dossier de destination
                if (!($historiqueDossier.Contains($fichierRelatif)) -Or !$synchroSuppression) { # Si le fichier n'est pas dans l'historique (ou que la suppression est désactivée)
                    Logger "Copie du fichier '$($fichierRelatif)' sur '$($destination)'..." 0
                    try { (Copy $fichier $fichierDest -ErrorAction 'SilentlyContinue') | Out-Null } # On copie le fichier sur la destination
                    catch { Logger "Une erreur est survenue durant la copie du fichier '$($fichierRelatif)' sur '$($destination)': $($_.Exception.Message)" 1 }
                }
                else { # Si le fichier existait avant (et que la suppression est activée)
                    Logger "Suppression du fichier '$($fichierRelatif)' sur '$($source)'..." 0
                    try { (Del $fichier -Recurse -ErrorAction 'SilentlyContinue') | Out-Null } # On le supprime
                    catch { Logger "Une erreur est survenue durant la suppression du fichier '$($fichierRelatif)' sur '$($destination)': $($_.Exception.Message)" 1 }
                }
            }
            else { # Si le fichier existe dans le dossier de destination
                try {
                    if ((Get-FileHash $fichier -ErrorAction 'SilentlyContinue') -ne (Get-FileHash $fichierDest -ErrorAction 'SilentlyContinue')) { # Si les hashs du fichier ne sont pas égaux

                        # On récupère les dates des fichiers
                        $dateOriginale = (Get-Item $fichier).LastWriteTime | Get-Date -UFormat %s
                        $dateDest = (Get-Item $fichierDest).LastWriteTime | Get-Date -UFormat %s

                        if ($dateOriginale -gt $dateDest) { # Si le fichier original est plus récent
                            Logger "Mise à jour du fichier '$($fichierRelatif)' sur '$($destination)'..." 0

                            try {
                                # On supprime et on copie le fichier original dans le dossier de destination
                                (Del $fichierDest -ErrorAction 'SilentlyContinue') | Out-Null
                                (Copy $fichier $fichierDest -ErrorAction 'SilentlyContinue') | Out-Null
                            }
                            catch { # Si il y a une erreur
                                Logger "Une erreur est survenue durant la mise à jour du fichier '$($fichierRelatif)' sur '$($destination)': $($_.Exception.Message)" 1
                            } 
                        }
                    }
                }
                catch {
                    Logger "Erreur à la vérification du hash de '$($fichierRelatif)' sur '$($destination)': $($_.Exception.Message)" 1
                }
            }

        }
    }
}

# Fonction qui renvoie un string contenant la liste des fichiers d'un dossier séparé par un pipe ('|')
function ListeFichier {
    param ($dirParam)

    $listeFichier = @()

    cd $dirParam

    # Pour chaque fichier dans le dossier (et sous-dossiers)
    Get-ChildItem $dirParam -Recurse | Foreach-Object {
        $fichier =  $_.FullName
        $fichierRelatif = (Resolve-Path $fichier -Relative).Substring(2)

        $listeFichier += $fichierRelatif
    }

    # On convertit l'array en strings séparés par des pipes
    $resultat = $listeFichier -join "|"

    return $resultat # On renvoie le résultat
}

$pathOriginal = Get-Location

try { # On test les path pour voir si ils existent
    $Dir1 = $(Resolve-Path $Dir1 -ErrorAction 'SilentlyContinue').ToString()
    $Dir2 = $(Resolve-Path $Dir2 -ErrorAction 'SilentlyContinue').ToString()
}
catch {
    Logger "Un des dossiers spécifiés n'existe pas." 2
    ArretErreur($retourErreur)
}


if($Dir1.ToLower() -eq $Dir2.ToLower()) {
    Logger "Vous ne pouvez pas synchroniser un dossier sur lui même." 2
    ArretErreur($retourErreur)
}

if ($checkHash) {
	#Récupération des hashs pour ne pas copier le dossier si ça n'est pas nécéssaire
	try { $Hash1 = Get-FolderHash $Dir1 } catch { $Hash1 = "0" }
	try { $Hash2 = Get-FolderHash $Dir2 } catch { $Hash2 = "0" }

	try {
		# On récupère la liste des fichiers des deux dossiers
		$listeFichier1 = ListeFichier $Dir1
		$listeFichier2 = ListeFichier $Dir2
	}
	catch {
		Logger "Erreur à la récupération de la liste des fichiers: $($_.Exception.Message)" 2
		cd $pathOriginal

		ArretErreur($retourErreur)
	}
}

# On vérifie via le hash et la liste des fichiers si il y a eu une modification dans l'un des deux dossiers
if ((($Hash1 -ne $Hash2) -Or ($listeFichier1 -ne $listeFichier2)) -Or !$checkHash) {
	if ($checkHash) {
		Logger "=================================" (-1)
		Logger "Nouveau contenu trouvé !" 0
	}

    try { # On récupère l'historique des fichiers sous forme d'array
        $contenuCSV = $((Get-Content $historiqueCSV -ErrorAction 'SilentlyContinue')[0])
        $ancienDir = $((Get-Content $historiqueCSV -ErrorAction 'SilentlyContinue')[1])

        if ($ancienDir -eq $($Dir1 + '|' + $Dir2)) {
            $historique = $contenuCSV.split('|')
        }
        else {
            Logger "Les dossiers à synchroniser ont changé." 0
            $historique = ""
        }
    }
    catch {
        Logger "Création du fichier d'historique '$($historiqueCSV)'..." 0
        $historique = ""

        try {
            $null > $historiqueCSV
            $($Dir1 + '|' + $Dir2) >> $historiqueCSV
        }
        catch {
            Logger "Une erreur est survenue durant la création du fichier d'historique '$($historiqueCSV)': $($_.Exception.Message)" 1
        }
    }

    try {
        # On appelle la fonction principale pour synchroniser les dossiers
        SynchroDossier $Dir1 $Dir2 $historique
        SynchroDossier $Dir2 $Dir1 $historique

        if ($checkHash) { Logger "Synchronisation terminée !" 0 }

        # On sauvegarde l'historique pour permettre d'identifier une suppression à une création pour la prochaine exécution
        try {
            ListeFichier $Dir1 > $historiqueCSV
            $($Dir1 + '|' + $Dir2) >> $historiqueCSV
        }
        catch {
            Logger "Une erreur est survenue durant la création de la liste des fichiers, la synchro de la suppression de fichier est altérée: $($_.Exception.Message)" 2
        }
    }
    catch {
        Logger "Une erreur est survenue durant la synchronisation des fichiers: $($_.Exception.Message)" 2
    }
}
else {
    Logger "Rien à faire."
}

cd $pathOriginal

# Fin du script
package security

import "errors"

func initThirdPartCipher(cipherPath string) error {
	return errors.New("third-party cipher not supported on macOS")
}

func cipherGetCount() int {
	return 0
}

func cipherGetInfo(seqno, cipherId, cipherName, _type, blkSize, khSIze uintptr) {
}

func cipherEncryptInit(cipherId, key, keySize, cipherPara uintptr) {
}

func cipherGetCipherTextSize(cipherId, cipherPara, plainTextSize uintptr) uintptr {
	return 0
}

func cipherEncrypt(cipherId, cipherPara, plainText, plainTextSize, cipherText, cipherTextBufSize uintptr) uintptr {
	return 0
}

func cipherClean(cipherId, cipherPara uintptr) {
}

func cipherDecryptInit(cipherId, key, keySize, cipherPara uintptr) {
}

func cipherDecrypt(cipherId, cipherPara, cipherText, cipherTextSize, plainText, plainTextBufSize uintptr) uintptr {
	return 0
}

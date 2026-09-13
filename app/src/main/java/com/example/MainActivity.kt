package com.example

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.fragment.app.FragmentActivity
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.example.data.FirebaseRepository
import com.example.ui.VibMainScreen
import com.example.ui.theme.MyApplicationTheme
import com.example.viewmodel.VibViewModel
import com.example.viewmodel.VibViewModelFactory

class MainActivity : FragmentActivity() {

  private val repository by lazy { FirebaseRepository(applicationContext) }
  private val viewModel: VibViewModel by viewModels { VibViewModelFactory(repository) }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    enableEdgeToEdge()
    setContent {
      MyApplicationTheme {
        VibMainScreen(viewModel = viewModel)
      }
    }
  }
}

@Composable
fun Greeting(name: String, modifier: Modifier = Modifier) {
  Text(text = "Hello $name!", modifier = modifier)
}

@Preview(showBackground = true)
@Composable
fun GreetingPreview() {
  MyApplicationTheme { Greeting("ALAA ELGNDY") }
}

